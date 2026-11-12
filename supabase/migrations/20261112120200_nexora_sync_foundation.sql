-- Phase 2B / 3 of 3: INERT sync foundation tables. No RPC, no client write grants: synchronization
-- stays disabled until the Phase 3 protocol and tests are approved. Rows will only ever be written
-- by a future SECURITY DEFINER RPC that derives user_id from auth.uid() (never from the payload).

create table public.devices (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  label text check (label is null or length(label) <= 100),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz,
  unique (id, user_id)
);

create table public.sync_operations (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,                      -- client generated; unique only within a user
  device_id uuid not null,
  entity_type text not null check (entity_type in ('project','task')),
  entity_id uuid not null,
  op_type text not null check (op_type in ('create','update','delete')),
  base_version bigint check (base_version is null or base_version > 0),
  patch jsonb not null default '{}'::jsonb,
  request_hash text not null,                      -- same operation_id + different hash => rejected
  client_created_at timestamptz,                   -- informational only; never used for ordering
  status text not null check (status in ('applied','conflict','rejected')),
  result jsonb,                                    -- stored response, replayed verbatim on retry
  applied_version bigint,
  server_seq bigint not null,
  received_at timestamptz not null default now(),
  primary key (user_id, operation_id),
  foreign key (device_id, user_id) references public.devices (id, user_id) on delete restrict
);
create index sync_operations_entity_idx on public.sync_operations (user_id, entity_type, entity_id);

create table public.sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  operation_id uuid not null,
  entity_type text not null check (entity_type in ('project','task')),
  entity_id uuid not null,
  fields text[] not null check (cardinality(fields) > 0),
  base_version bigint not null,
  server_version bigint not null,
  server_value jsonb not null,
  client_value jsonb not null,
  status text not null default 'open' check (status in ('open','resolved_server','resolved_client','resolved_merged')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  foreign key (user_id, operation_id) references public.sync_operations (user_id, operation_id) on delete cascade,
  check ((status = 'open') = (resolved_at is null))
);
create index sync_conflicts_open_idx on public.sync_conflicts (user_id, status);

alter table public.devices enable row level security;
alter table public.sync_operations enable row level security;
alter table public.sync_conflicts enable row level security;

revoke all on public.devices, public.sync_operations, public.sync_conflicts from anon, authenticated;
grant select on public.devices, public.sync_operations, public.sync_conflicts to authenticated;

create policy devices_owner_select on public.devices for select to authenticated using (user_id = (select auth.uid()));
create policy sync_operations_owner_select on public.sync_operations for select to authenticated using (user_id = (select auth.uid()));
create policy sync_conflicts_owner_select on public.sync_conflicts for select to authenticated using (user_id = (select auth.uid()));
