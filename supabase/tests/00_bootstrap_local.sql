-- LOCAL TEST FIXTURE ONLY. Never applied to the hosted project.
-- Recreates the Supabase roles/auth stubs and the state produced by
-- 20261112111349_nexora_initial_domain_schema (as observed in the live catalog).
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), is_anonymous boolean not null default false);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

create function public.rls_auto_enable() returns event_trigger language plpgsql security definer
set search_path = pg_catalog as $$
declare cmd record;
begin
  for cmd in select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') and object_type in ('table','partitioned table')
  loop
    if cmd.schema_name = 'public' then
      execute format('alter table if exists %s enable row level security', cmd.object_identity);
    end if;
  end loop;
end $$;
create event trigger ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE','CREATE TABLE AS','SELECT INTO') execute function public.rls_auto_enable();
grant execute on function public.rls_auto_enable() to anon, authenticated, service_role;

create function public.nexora_set_updated_at() returns trigger language plpgsql set search_path = '' as
$$ begin new.updated_at = now(); return new; end $$;
revoke execute on function public.nexora_set_updated_at() from public, anon, authenticated;

create table public.profiles (id uuid primary key references auth.users(id) on delete cascade,
  display_name text, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.projects (id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete restrict,
  name text not null check (length(btrim(name)) between 1 and 200), description text, color text,
  is_archived boolean not null default false, sort_order numeric not null default 0,
  version bigint not null default 1 check (version > 0), deleted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (id, owner_id));
create index projects_owner_active_idx on public.projects (owner_id, deleted_at);
create table public.tasks (id uuid primary key default gen_random_uuid(),
  project_id uuid not null, owner_id uuid not null, parent_id uuid,
  title text not null check (length(btrim(title)) between 1 and 500), notes text,
  status text not null default 'open' check (status in ('open','in_progress','ready_for_review','done')),
  priority text not null default 'medium' check (priority in ('low','medium','high')),
  due_date date, completed_at timestamptz, sort_order numeric not null default 0,
  version bigint not null default 1 check (version > 0), deleted_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (parent_id is null or parent_id <> id),
  unique (id, project_id),
  foreign key (project_id, owner_id) references public.projects (id, owner_id) on delete restrict,
  foreign key (parent_id, project_id) references public.tasks (id, project_id) on delete restrict);
create index tasks_project_parent_idx on public.tasks (project_id, parent_id, sort_order);
create index tasks_owner_updated_idx on public.tasks (owner_id, updated_at);
create table public.project_members (project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('viewer','editor')), created_at timestamptz not null default now(),
  primary key (project_id, user_id));
create index project_members_user_idx on public.project_members (user_id);

create policy profiles_self_select on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy profiles_self_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_self_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy projects_owner_select on public.projects for select to authenticated using (owner_id = (select auth.uid()));
create policy projects_owner_insert on public.projects for insert to authenticated with check (owner_id = (select auth.uid()));
create policy projects_owner_update on public.projects for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy projects_owner_delete on public.projects for delete to authenticated using (owner_id = (select auth.uid()));
create policy tasks_owner_select on public.tasks for select to authenticated using (owner_id = (select auth.uid()));
create policy tasks_owner_insert on public.tasks for insert to authenticated with check (owner_id = (select auth.uid()));
create policy tasks_owner_update on public.tasks for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy tasks_owner_delete on public.tasks for delete to authenticated using (owner_id = (select auth.uid()));
create policy project_members_owner_select on public.project_members for select to authenticated using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy project_members_owner_insert on public.project_members for insert to authenticated with check (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy project_members_owner_update on public.project_members for update to authenticated using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = (select auth.uid()))) with check (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = (select auth.uid())));
create policy project_members_owner_delete on public.project_members for delete to authenticated using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = (select auth.uid())));

-- Hosted initial migration also attached these triggers (verified read-only on the live catalog).
create trigger profiles_updated_at before update on public.profiles for each row execute function public.nexora_set_updated_at();
create trigger projects_updated_at before update on public.projects for each row execute function public.nexora_set_updated_at();
create trigger tasks_updated_at before update on public.tasks for each row execute function public.nexora_set_updated_at();
