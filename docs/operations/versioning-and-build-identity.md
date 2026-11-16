# Application version and build identity

How to tell exactly which build is running, how to raise the version, and how to trace a released artifact back to its source.

## 0. Which Windows build is which
| Build | Workflow and artifact | `BUILD-INFO.json` | About shows |
|---|---|---|---|
| **Local-only release build** | `ci.yml`, artifact `nexora-windows-portable` (`nexora-windows-portable.zip`) | `buildType: release`, `syncEnabled: false` | Build **Release build**, Synchronization **Off: local only, no sign-in**; no Sign in anywhere in the app |
| **Sign-in and synchronization DEVELOPMENT TEST build** | `windows-sync-dev-build.yml`, artifact `nexora-windows-sync-DEVELOPMENT-TEST` (`nexora-windows-sync-DEVELOPMENT-TEST.zip`) | `buildType: development-test`, `syncEnabled: true` | Build **DEVELOPMENT TEST** (warning colour and note), Synchronization **On: sign-in and sync (TEST project)**; the sync card and Sign in |
| A developer's own build | none | none | Build **Local build (not made by CI)**, commit **unknown** |

The two CI builds have the same version and (for one commit) the same source commit; they differ in build type and `syncEnabled`. The sync build embeds only the public URL and anon key of the TEST project (a key whose role is not `anon` is refused by the app and by the workflow); no service-role key, token or password is built in, logged or shown. The workflow starts by a manual dispatch, or by a push to `feature/phase-5-ui-ux` that touches the workflow file.

## 1. One source of truth
The version is the `version:` line of `pubspec.yaml` (`x.y.z+n`). Nothing else is edited by hand:

| Where it appears | How it is derived |
|---|---|
| `nexora.exe` file/product version (Windows Explorer, Properties) | Flutter's build tooling writes it from `pubspec.yaml` into `windows/runner/Runner.rc` (`FLUTTER_VERSION_*`) |
| About screen (Nexora version) | the app reads its own bundled `pubspec.yaml` (declared as an asset) and parses that line; there is no copy of the number in Dart |
| `BUILD-INFO.json` and `SHA256SUMS.txt` in CI artifacts | `tool/write_build_info.ps1` reads `pubspec.yaml` |

Current version: **1.1.0+2** (was 1.0.0+1; the release version rises because the local file schema, the synchronization protocol and the interface changed). Raising the version: edit the one `version:` line (`1.0.0+1` became `1.1.0+2`), commit, and let CI build. The part before `+` is the release version; the part after is a build counter you raise when you ship another build of the same release. Do not edit `Runner.rc`, a Dart constant or a workflow for this.

## 2. The identity CI writes
Both Windows workflows pass three values to `flutter build windows` as `--dart-define`s and write a file next to `nexora.exe`:

| Value | CI source | Meaning |
|---|---|---|
| `NEXORA_COMMIT` | pull request: `github.event.pull_request.head.sha`; any other run: `github.sha` | the commit the work is on (40 hex characters) |
| `NEXORA_BUILD_TYPE` | `release` in `ci.yml`; `development-test` in `windows-sync-dev-build.yml` | which build this is |
| `NEXORA_BUILD_RUN` | `<run id>-<run attempt>` | find the workflow run |

A pull request is built from GitHub's test merge of the head into the base, so the checked-out commit (`GITHUB_SHA`) is that merge commit, not a commit on the branch. The identity therefore records the **head commit** as the source and keeps the merge commit separately in `BUILD-INFO.json` (`checkoutCommit`). For a push to `main` or a manual run they are the same.

`BUILD-INFO.json` (inside the ZIP next to `nexora.exe`, and as a separate artifact file) holds: `version`, `buildNumber`, `buildType`, `sourceCommit`, `sourceShort`, `checkoutCommit`, `ciRun`, `builtAtUtc`. It contains no secrets, URLs or account data. `SHA256SUMS.txt` repeats `commit`, `version` and `run`. ZIP file names are unchanged (`nexora-windows-portable.zip`, `nexora-windows-sync-DEVELOPMENT-TEST.zip`), so the distribution workflow is unchanged; the identity travels in the metadata.

## 3. What the About screen shows
Account menu (bottom of the sidebar), **About Nexora**:

| Field | Value |
|---|---|
| Version | `1.0.0+1` from `pubspec.yaml`; `unknown` if the bundled file cannot be read |
| Synchronization | `On: sign-in and sync (TEST project)` or `Off: local only, no sign-in`, from the build-time flag `NEXORA_SYNC` (it travels in `BUILD-INFO.json` as `syncEnabled`) |
| Source commit | first seven characters of `NEXORA_COMMIT`; **`unknown`** when it was not provided or is not a valid commit id. Never guessed |
| Build | `Release build`, **`DEVELOPMENT TEST`** (warning colour, with a note that it is not a release), or `Local build (not made by CI)` |
| CI run | only when provided |

"Copy details" puts those same lines on the clipboard for a bug report. A build made without the defines (for example `flutter run`, or a developer's own `flutter build`) is a **local build**: it shows the version, an unknown commit and says the commit cannot be confirmed.

### Local builds that should carry a commit
Only when you want one: `flutter build windows --release --dart-define=NEXORA_BUILD_TYPE=local --dart-define=NEXORA_COMMIT=$(git rev-parse HEAD)`. Append `-dirty` to the commit if the working tree has changes (`…=<sha>-dirty`); the About screen shows it. The build type stays "Local build" so it can never be mistaken for a CI artifact.

## 4. Trace a released artifact to its source
1. Download the artifact; read `BUILD-INFO.json` (or the first lines of `SHA256SUMS.txt`) for `sourceCommit`, `version`, `ciRun`.
2. The same commit is in the running app: About Nexora, Source commit (first seven characters) and "Copy details" (full commit).
3. `git show <sourceCommit>` (or the commit page on GitHub) is the exact source of the head; the workflow run `<run id>` (the part of `ciRun` before `-`) is the build; the SHA-256 of the ZIP is the first line of `SHA256SUMS.txt`.
4. Check the version: `git show <sourceCommit>:pubspec.yaml` has the same `version:` line.
5. A Windows build whose About shows a different commit than its `BUILD-INFO.json` was not built by that workflow.

## 5. Tests
`test/core/build_info_test.dart` (parsing, commit validation, build types, unknown fallbacks, report), `test/app/about_test.dart` (About display for release, DEVELOPMENT TEST, local and missing metadata; copy; the loader reading the real bundled `pubspec.yaml` and matching its `version:` line).
