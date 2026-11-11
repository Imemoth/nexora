# Nexora

Private, offline-first task and notes app. V1 targets a portable Windows ZIP. Android and iOS follow later. See `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`.

## Toolchain (pinned)
- Flutter **3.47.9** (stable), Dart **3.13.7**. Pinned in CI (`FLUTTER_VERSION` in `.github/workflows/ci.yml`) and recorded in `.metadata`.
- Third-party GitHub Actions are pinned to commit SHAs.
- The owner's machine does not need the Flutter SDK. CI builds and tests the app.

## Windows support
- **Minimum:** Windows 10 (64-bit, x64). Flutter 3.47 lists Windows 10 and 11 as supported and tests Windows 10 in CI. Windows 8 and earlier are unsupported.
- **Local builds (optional):** Visual Studio with the "Desktop development with C++" workload, and Flutter 3.47.9.
- **Known limitations (Phase 0):** no notifications, tray, or reminders yet (Phase 4). Corporate policies may block unsigned executables or extraction paths. Test on a clean machine before release.

## Development
```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
```

## Portable ZIP
`tool/package_windows.ps1` packages the full Release bundle (`nexora.exe`, Flutter engine DLLs, and `data/`). Extract the ZIP anywhere and run `nexora.exe`. No installer is needed.

## Configuration and secrets
Phase 0 does not connect to Supabase, and the app runs with no configuration. Never commit `.env` files, service-role keys, connection strings, or tokens. Supabase access is documented in `docs/operations/supabase-access.md`.
