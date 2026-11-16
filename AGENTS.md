# Agent rules for Nexora (read first)

Full policy: [`docs/development-environment-policy.md`](docs/development-environment-policy.md). Status of the project: [`docs/coordination/status-register.md`](docs/coordination/status-register.md). Map: [`docs/README.md`](docs/README.md).

1. Nexora is **DEVELOPMENT/TEST only. No production environment exists.**
2. Supabase `uicccaawtjvqggeufbez` is a **DEV/TEST database**; all current data is mock or test data.
3. **Do not impose unjustified production-grade requirements** (migration choreography, rollback plans, release processes, legacy or old-client compatibility). Prefer the simplest correct change and update code, tests and docs together.
4. **Still mandatory:** proper tests, RLS, authentication, data integrity. Never put a service-role key or any secret in the app, a build, a log or a document.
5. **DEV/TEST is not permission:** hosted writes (migrations, data, configuration, permissions, Auth) and any destructive action need the owner's **separate, explicit authorization of that exact operation**. Use a disposable local or CI database for tests.
6. Valid for all future phases and every AI-agent session. Do not merge pull requests or mark Draft PRs ready without the owner.

A Nexora kizárólag DEV/TEST fázisban van; production nincs; hosted íráshoz és destruktív művelethez külön tulajdonosi engedély kell.
