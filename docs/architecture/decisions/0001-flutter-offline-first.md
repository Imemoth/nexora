# 0001: Flutter client with offline-first local store and Supabase as cross-device authority

Status: accepted (Phase 0, 2026-11-11). Source: `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`.

## Context
Nexora V1 is a personal, offline-first task and notes app. It must run as a portable Windows ZIP, and later on Android and iOS. Data must survive restarts without a network, and must sync across devices later without silent data loss.

## Decision
- **Client framework:** Flutter. Targets: Windows (V1), Android and iOS (later). Dart domain code has no Flutter or database imports so it can be shared.
- **Local source of truth for the UI:** SQLite on the device. Editing is local-first with autosave and a durable outbox (Phase 2).
- **Cross-device authority:** Supabase Postgres, Auth, and RLS (Phase 3). The client uses only the publishable key and the signed-in user's JWT.
- **Repository boundary:** `lib/features/<feature>/domain` is pure Dart. Widgets, SQLite, and the Supabase client sit outside the domain.
- **Parent completion:** a parent's status is never derived automatically from its children. Children completing moves the parent to review only; closing the parent is a manual action.

## Consequences
- Phase 0 has no database or network code. The app must boot with no configuration.
- Windows is the first build target, so Windows-specific gaps (notifications, tray) are tracked in Phase 4.
- The Supabase service-role key never appears in client code, CI, or the repository.
- Supabase hosted changes need separate owner approval (see `docs/operations/supabase-access.md`).

## Alternatives considered
- **Web-only app:** rejected. Offline reliability and a portable desktop ZIP are V1 goals.
- **Native per-platform apps:** rejected for V1. Duplicated domain logic and a larger maintenance surface.
- **Last-write-wins sync:** rejected. Spec requires preserving both versions on concurrent same-field edits.
