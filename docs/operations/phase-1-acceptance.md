# Phase 1 — Live Acceptance Package

Status: **prepared for owner Live Acceptance. Not accepted.** Automated gates are green on the final code head. The manual checks in section 8 are the owner's to run and record. Nothing in this document claims that manual acceptance has passed.

Scope: a fully offline, in-memory Windows desktop prototype with deterministic demo data. Phase 1 has **no durable storage**. Nothing is saved between runs, and no SQLite, Supabase, network or authentication code exists in the app.

---

## 1. Final integrated code head

| Item | Value |
|---|---|
| Repository | `Imemoth/nexora` |
| Final code head (tested) | `3be43876f5` on branch `feature/phase-1-golden` (PR #11) |
| Full commit | `3be43876f57ca7d9ce28c5ac6be231c988a1edc0` |
| This document's commit | documentation-only commit on `feature/phase-1-acceptance` (stacked on the code head). It changes no code. |
| Final CI run (code head) | [43188559503](https://github.com/Imemoth/nexora/actions/runs/43188559503) — **success** |
| Toolchain | Flutter 3.47.9 (stable), Dart 3.13.7, `windows-latest` GitHub Actions runner |

The code head contains every Phase 1 task (2 through 8). The stacked PRs listed in section 2 are verified ancestors of it.

---

## 2. Implementation PRs and dependency order

Execution order is strictly linear. Each PR's base is the PR above it. None is merged into `main`. All are Draft.

| Order | PR | Task | Branch | Head at last CI | Base | State |
|---|---|---|---|---|---|---|
| 0 | [#4](https://github.com/Imemoth/nexora/pull/4) | Task 1: pure domain | `feature/phase-1-domain` | `b746db8` | `main` | merged into `main` (`c1c1557`), owner-approved |
| 1 | [#5](https://github.com/Imemoth/nexora/pull/5) | Task 2: application workspace | `feature/phase-1-application` | `ee56e7a` (CI success) | `main` | Draft |
| 2 | [#6](https://github.com/Imemoth/nexora/pull/6) | Task 3: shell and sidebar | `feature/phase-1-shell` | `86b5c7d` (CI success) | #5 | Draft |
| 3 | [#7](https://github.com/Imemoth/nexora/pull/7) | Task 4: task tree, search, sort | `feature/phase-1-tree` | `22ab5ce` (CI success) | #6 | Draft |
| 4 | [#8](https://github.com/Imemoth/nexora/pull/8) | Task 5: editor, creation, unsaved-change gate, exit gate | `feature/phase-1-editor` | `3bff274` (CI success) | #7 | Draft |
| 5 | [#9](https://github.com/Imemoth/nexora/pull/9) | Task 7: responsive overlay, palette, accessibility | `feature/phase-1-responsive-lead` | `4f51abe` (CI success) | #8 | Draft |
| 6 | [#10](https://github.com/Imemoth/nexora/pull/10) | Tasks 6+7 integration (keyboard merged in) | `feature/phase-1-integration` | `622cf0e` (CI success) | #9 | Draft |
| 7 | [#11](https://github.com/Imemoth/nexora/pull/11) | Task 8: goldens and baselines | `feature/phase-1-golden` | `3be4387` (CI success) | #10 | Draft — **final integrated code head** |
| 8 | this PR (Task 9) | acceptance documentation | `feature/phase-1-acceptance` | docs-only | #11 | Draft |

Notes on the stack:
- Task 6 (keyboard) was developed on `feature/phase-1-keyboard` and merged into the integration branch. It has no separate PR, to avoid running CI twice on the same code.
- PRs #5 to #10 are superseded by #11 for the final verification. Their heads are verified ancestors of `3be4387`.
- PR #1 (`docs/phase-0-implementation-plan`, a Phase 0 documentation PR) is still open as a Draft. It is not part of Phase 1 and is listed for the owner to close or keep.

---

## 3. CI results

All gates ran on `windows-latest` with the pinned toolchain.

| Gate | Result on final head (run 43188559503) |
|---|---|
| Flutter and Dart version verification | pass (Flutter 3.47.9; Dart 3.13.7) |
| Dependency resolution (`flutter pub get`) | pass |
| Dart formatting (`dart format --set-exit-if-changed`) | pass |
| Analyzer (`flutter analyze`) | pass — "No issues found!" |
| Full real Flutter test suite (`flutter test`) | pass — **262 tests passed**, including architecture, domain, application, widget, keyboard, accessibility, responsive and golden tests |
| Windows release build (`flutter build windows --release`) | pass |
| Portable ZIP packaging (`tool/package_windows.ps1`) | pass — "PACKAGE PASS" |
| Unicode and spaces path smoke test | pass — launched from `…\nexora smoke é测试 0950db4b`, closed cleanly, exit 0 |
| Artifact upload | pass |

The run before the final one (run 43188539877 on `95105ec`) was cancelled by the concurrency rule when a newer commit arrived, so it is not evidence. The run that failed before it (43185856604 on `7af3635`) failed on one analyzer finding, which is fixed in `95105ec` and `3be4387`.

### Earlier CI failures, fixed during the work (for traceability)

These are listed so the owner can see the repair history. Each was fixed with a regression test or a lint correction. None is open.

- Task 5: analyzer errors on `AppExitResponse`/`AppExitType` (defined in `dart:ui` at this Flutter version) — `10e532a`.
- Task 5: 22 widget tests broken by a 88 px overflow in the editor action row — `aed8cfd`.
- Task 5: text-finder ambiguity (indicator and dialog title both "Unsaved changes") — `3bff274`.
- Task 6/7: duplicate "New task" text in a keyboard test; redundant imports — `622cf0e`, `2ce9f6c`.
- Task 8: the golden generator stalled because a piped `flutter --version | head` closed the Flutter tool's output pipe, which made the tool retry forever — `d6ef667`.

---

## 4. Test counts

| Source | Count | Status |
|---|---|---|
| Real `flutter test` on the final head (CI run 43188559503) | **262 passed, 0 failed** | official |
| Local stand-in runner (non-widget tests only, Dart SDK 3.13.7, no Flutter) | 182 passed, 0 failed | informational only; not a substitute for CI |

The local stand-in cannot execute widget tests. It was used only for fast checks of domain, application, architecture and contrast logic. Official evidence is the CI figure.

### What the automated tests cover

- **Domain** (Task 1): parent-change rules, creation rules, title validation, calendar dates, smart views, ordering, search, completion summaries.
- **Application** (Tasks 2 and 5): workspace state, the unsaved-change gate for every transition in the plan's table, failed-save and failed-create invariants, the transactional Discard decision, duplicate and concurrent operation guards, the reveal rule for new tasks, exit gating.
- **Architecture**: no Flutter import in core, domain or application; no SQLite, Supabase or HTTP package anywhere in `lib/`; no visible-text literals outside `AppStrings`.
- **Widget** (Tasks 3 to 7): shell layout, sidebar counts, task tree (expand/collapse, done/total, Ready for review), search, sort, empty states, the editor (Save/Revert enabled only when dirty, validation, failed-save message), creation dialogs, the unsaved-change dialog, exit flows, keyboard shortcuts with focus restoration, responsive breakpoints (overlay, desktop-only notice), text scale 1.3 without overflow, tooltips and 40 px hit targets.
- **Contrast** (Task 7, pure Dart): every text token against every surface, 4.5:1 normal text and 3:1 large text. The lowest pair is `textMuted` on `surface2` at about 5.1:1.
- **Golden** (Task 8): two pixel comparisons on the pinned runner (see section 5).

---

## 5. Golden baselines

| File | Scenario |
|---|---|
| `test/golden/goldens/all_view_selected.png` | All view at 1280×800 with one task selected |
| `test/golden/goldens/empty_state.png` | Empty state ("No tasks here yet") at 1280×800 |

- Generated on `windows-latest` with Flutter 3.47.9 by a temporary push-triggered workflow (run 43185260570, commit `d6ef667`). The workflow was removed in the commit that added the baselines.
- Demo data is fixed to a date, so the output is deterministic. Test font rendering uses Flutter's built-in test font, which draws glyphs as blocks. **The goldens therefore prove layout, colour and structure, not the final typeface.** The real Windows font is a manual check (section 8).
- The goldens were checked by eye after generation: the selected row is highlighted, and the empty state shows its message.

---

## 6. Artifact metadata

| Item | Value |
|---|---|
| Artifact name (GitHub) | `nexora-windows-portable` |
| Artifact ID | `13929533389` |
| Produced by | run [43188559503](https://github.com/Imemoth/nexora/actions/runs/43188559503), commit `3be43876f5` |
| Download (owner) | GitHub Actions run page → Artifacts → `nexora-windows-portable`. Or: `gh run download 43188559503 --repo Imemoth/nexora --name nexora-windows-portable` |
| Outer artifact size | 12,005,239 bytes |
| **Outer artifact SHA-256** (GitHub container, verified equal to the API digest `sha256:1df5a63d…`) | `1df5a63dc40afb65481b042533647eaa37205ca14e3494cd77d51cb7d53a5c02` |
| Inner application ZIP name | `nexora-windows-portable.zip` |
| Inner application ZIP size | 12,011,972 bytes |
| **Inner application ZIP SHA-256** | `ae7f65025bce0237c182994f9ef61dea9ffa52d5aa109e741c59b17bc7782649` |
| Inner ZIP integrity | `unzip -t`: no errors detected |
| Inner ZIP entries | 14 (listed below) |

### Verification steps (owner, PowerShell or Git Bash)

```bash
# 1. Outer container (the GitHub artifact)
sha256sum nexora-windows-portable-outer.zip   # expect 1df5a63d…c02

# 2. Inner application ZIP
sha256sum nexora-windows-portable.zip         # expect ae7f6502…2649
unzip -tq nexora-windows-portable.zip         # expect "No errors detected"
unzip -Z1 nexora-windows-portable.zip | wc -l # expect 14
```

PowerShell equivalent: `Get-FileHash -Algorithm SHA256 <file>`.

### Inner ZIP contents (14 entries)

```
data/app.so
data/flutter_assets/AssetManifest.bin
data/flutter_assets/FontManifest.json
data/flutter_assets/NOTICES.Z
data/flutter_assets/NativeAssetsManifest.json
data/flutter_assets/fonts/MaterialIcons-Regular.otf
data/flutter_assets/packages/cupertino_icons/assets/CupertinoIcons.ttf
data/flutter_assets/shaders/ink_sparkle.frag
data/flutter_assets/shaders/stretch_effect.frag
data/icudtl.dat
flutter_windows.dll
nexora.exe
```

(`data/flutter_assets/packages/` and `packages/cupertino_icons/` appear as directory entries in the listing; the 14 counts include them as the ZIP reports them.)

### Smoke test evidence (from CI log)

- `OK: ZIP contains 14 entries including all required runtime files`
- `OK: release bundle complete`
- `SMOKE PASS: launched from 'C:\Users\runneradmin\AppData\Local\Temp\nexora smoke é测试 0950db4b', closed cleanly (exit 0)`
- `PACKAGE PASS: D:\a\nexora\nexora\dist\nexora-windows-portable.zip`

---

## 7. Feature inventory (what the prototype does)

### Navigation and layout
- Three panes at 1100 px and wider: sidebar (240 px), task list, details editor (360 px).
- 900 to 1099 px: the details editor becomes an overlay over the list while a task is selected. Closing it goes through the same unsaved-change gate as selection.
- Below 900 px: a desktop-only notice shows; the list stays usable; no overlay opens.
- Sidebar: Today, Next 7 Days, Overdue, All, and a Projects section. Each entry shows a live count that ignores the search query.
- The default view is All.

### Task tree and list
- Recursive hierarchy with expand/collapse. Children appear only under expanded parents.
- Each row shows: indentation by depth, status (text), due date (ISO), priority (text), and done/total for parents.
- A parent whose children are all done shows **Ready for review**. Its status is never changed automatically.
- Search over title and notes, case-insensitive. The result count includes children hidden under collapsed parents.
- Sort: position, due date, priority, title. Sorting changes only the display order.
- Empty states: no matches (with a Clear action), empty project, empty smart view.
- If a collapse hides the selected task, the list says: "Selected task is hidden in this view."

### Editing
- Title, status, priority, date-only due date (picker and clear), and plain-text notes.
- Save and Revert are enabled only for a dirty draft. An "Edited, not saved" indicator shows while the draft is dirty.
- Validation: an empty or over-200-character title is refused, and nothing is saved.
- Save failures keep the edits and show an error message.
- Add subtask is disabled for an archived draft.

### Creation
- New task (root) in a project, with a project selector.
- Subtask under a non-archived task. It expands the parent and selects the child.
- An undated task is hidden in Today, Next 7 Days and Overdue. Creating one from those views moves the selection to its project and clears a search that hides it. The task never receives a due date.

### Unsaved changes (the gate)
- Selecting another task, changing view, project or search, clearing selection, creating, and exiting all pass through one gate when the draft is dirty. Sorting and expanding do not.
- The dialog offers Save, Discard and Cancel. A failed save keeps the dialog open with the error.
- **Discard (owner-approved behaviour, 2026-11-12):** Discard is committed only when the pending transition succeeds. If a pending create fails after Discard, the dirty draft, the selection and the pending create are all kept, and the error is shown. The user can retry or cancel, and cancel keeps every edit.
- Duplicate and concurrent operations are refused: a second Save, Discard or create while one is running is not executed.

### Exit
- Closing the app with a dirty draft opens the same dialog and cancels the exit. Save or Discard then exits.
- A failed save during exit does not exit.

### Keyboard (Ctrl is the command key; no Cmd binding)

| Key | Action |
|---|---|
| Up / Down | Move selection through visible rows (through the gate) |
| Right / Left | Expand or collapse; Left moves to the parent when collapsed |
| Enter | Focus the title field of the selected task |
| Esc | In the editor or search, return focus to the list. Elsewhere, clear the selection (through the gate). See section 9 for the deviation. |
| Ctrl+F | Focus the search field |
| Ctrl+N | Open the New task dialog |
| Ctrl+Shift+N | Open the New subtask dialog for the selected task (not for archived tasks) |
| Ctrl+S | Save the dirty draft |
| Ctrl+Z (in a text field) | Standard text undo; not intercepted |

Keys reach the shortcuts only when focus is inside the list or the editor. The sidebar is not covered by the keymap.

### Appearance
- Dark theme only. No light theme (decision 7).
- Contrast of every text token meets WCAG 4.5:1 for normal text.
- Icon-only buttons have tooltips. Row actions are at least 40×40 logical pixels.

---

## 8. Manual Live Acceptance checklist (owner)

Run the artifact from section 6 on a Windows 10 x64 machine (or Windows 11). Record a pass or fail and a short note for each item. Use a path with spaces and a non-ASCII character to extract the ZIP, to match the automated smoke test.

### A. Setup
- [ ] A1. Verify the outer and inner SHA-256 values in section 6. Record the values you computed.
- [ ] A2. Extract the inner ZIP to a folder whose path contains a space and a non-ASCII character. Confirm all 14 entries exist.
- [ ] A3. Confirm no installer or admin rights are needed.

### B. Launch and exit
- [ ] B1. Double-click `nexora.exe`. The window opens with the title "Nexora" and the dark theme.
- [ ] B2. The default view is All, and the sidebar shows Today, Next 7 Days, Overdue, All and Projects (Home, Work).
- [ ] B3. Close the window with the close button. The app exits. The process is gone from Task Manager.
- [ ] B4. Close the window with Alt+F4 while a draft is dirty (see J). The dialog appears and the app does not close.

### C. Layout
- [ ] C1. At full width (at least 1100 px) the sidebar, list and details editor show side by side.
- [ ] C2. Resize the window to between 900 and 1099 px. Select a task. The editor appears as an overlay on the right. Close it with its × button.
- [ ] C3. Resize to below 900 px. The desktop-only notice shows. The list still works. No overlay opens.
- [ ] C4. Set the Windows display scale to 125% and then 150%. Nothing is cut off, and the buttons still show their text.

### D. Smart views and projects
- [ ] D1. Today shows the task "Plan weekend groceries" and the count is 1 (demo data is fixed to the date the build was made, so the counts may differ if the date has changed).
- [ ] D2. Overdue and Next 7 Days show tasks with the expected counts for the build date.
- [ ] D3. Click Home and Work. Each shows only its own tasks, and its header and count update.
- [ ] D4. The sidebar counts do not change when you type in the search box.

### E. Task hierarchy
- [ ] E1. "Plan spring trip" in Home has a chevron and shows "1/2". Click the chevron. Its two subtasks appear. Click again. They hide.
- [ ] E2. The chevron does not select the task.
- [ ] E3. A row with no children has no chevron.
- [ ] E4. "Quarterly review" in Work shows "1/2" and its status is unchanged.

### F. Creation
- [ ] F1. Click New task. Enter a title, pick a project, press Enter. The dialog closes, "Task created" appears, and the new task is selected.
- [ ] F2. In Today, create a new task. It is not shown in Today (it has no due date), but the view switches to its project and the new task is selected. Confirm no due date was added.
- [ ] F3. Select a task, click Add subtask. Enter a title and submit. The parent expands and the new child is selected.
- [ ] F4. Click New task, leave the title empty, and press Create. The message "Enter a title." appears and the dialog stays open.
- [ ] F5. Type 201 characters in the title. The message "Use 200 characters or fewer." appears.

### G. Editing, Save and Revert
- [ ] G1. Select a task. Save and Revert are disabled. The "Edited, not saved" indicator is not shown.
- [ ] G2. Change the title. The indicator appears, and Save and Revert are enabled.
- [ ] G3. Click Revert. The title returns to the saved value. The indicator disappears.
- [ ] G4. Change the title and click Save. The row in the list shows the new title.
- [ ] G5. Change the status from the dropdown. Change the priority. Set a due date with the picker. Clear it with the clear button. Each change marks the draft dirty.
- [ ] G6. Type notes across several lines. They are saved as plain text.
- [ ] G7. Clear the title and click Save. "Enter a title." appears, and nothing is saved.
- [ ] G8. Open an archived task (set the status to Archived and save). Add subtask is disabled.

### H. Unsaved-change protection
- [ ] H1. Edit a task. Click another task. The dialog "Unsaved changes" appears, and the first task stays selected.
- [ ] H2. Click Cancel. The dialog closes and your edit is still in the editor.
- [ ] H3. Click another task, then Discard. The other task is selected and the edit is gone.
- [ ] H4. Click another task, then Save. The edit is saved and the other task is selected.
- [ ] H5. Change the view or project while a draft is dirty and the task would be hidden. The dialog appears.
- [ ] H6. Expand or collapse a parent with a dirty draft. No dialog appears (expanding and collapsing never gate).
- [ ] H7. Change the sort order with a dirty draft. No dialog appears.

### I. Failed-save behaviour (Discard exception)
- [ ] I1. The app cannot be forced to fail a save from the UI, so this item is covered by automated tests (`task_workspace_transaction_test.dart`, `editor_test.dart`). Owner: confirm you accept this as evidence, or request a manual fault-injection build.
- [ ] I2. Confirm the Discard exception described in section 7 matches what you expect.

### J. Exit protection
- [ ] J1. With a dirty draft, click the window close button. The dialog appears and the app stays open.
- [ ] J2. In the dialog, click Save. The app closes after saving. Restart and confirm the change is **not** there (no durable storage, see section 9).
- [ ] J3. Repeat with Discard. The app closes without saving.
- [ ] J4. Repeat with Cancel. The app stays open and the edit is kept.
- [ ] J5. Click the close button several times quickly with a dirty draft. Only one dialog is open.
- [ ] J6. Alt+F4 behaves like the close button (J1 to J4).

### K. Search and sort
- [ ] K1. Click the search box and type "bike". Only "Repair bike" shows. The count is "1 task".
- [ ] K2. Type "zzzz". "No tasks match your search" appears with a Clear button. Click Clear. All tasks return.
- [ ] K3. Search matches notes too: type "offers". The task "Renew car insurance" shows.
- [ ] K4. Open the sort menu. Choose Due date. Overdue tasks come first. Choose Title. The list is alphabetical.

### L. Keyboard
- [ ] L1. Click a task, then press Down and Up. The selection moves through visible rows.
- [ ] L2. Press Right on a parent to expand it, and Left to collapse it.
- [ ] L3. Press Enter with a task selected. The title field is focused.
- [ ] L4. Press Ctrl+F. The search box is focused. Type to search.
- [ ] L5. Press Ctrl+N. The New task dialog opens with the title focused. Press Esc or Cancel. Focus returns to the list.
- [ ] L6. Select a task that is not archived and press Ctrl+Shift+N. The New subtask dialog opens.
- [ ] L7. Edit a title, press Ctrl+S. The change is saved.
- [ ] L8. Inside the title field, press Ctrl+Z after typing. The text undo works and is not blocked by a shortcut.
- [ ] L9. With a dirty draft, press Down. The unsaved-change dialog appears, the same as with the mouse.
- [ ] L10. Complete flows L5, L6 and L7 without touching the mouse.

### M. Accessibility
- [ ] M1. Tab through the sidebar, the list, the search box, the sort menu, and the editor. The focus ring is visible on every control.
- [ ] M2. Hover over the chevron, the close button and the sort menu. Each shows a tooltip.
- [ ] M3. Status and priority are readable as text without colour.
- [ ] M4. Read the text on screen at 100% and at 150% scale. It is readable and nothing overlaps.
- [ ] M5. Optional: run Windows Narrator and confirm the list rows and buttons are announced.

### N. Restart behaviour (expected data loss)
- [ ] N1. Create a task and edit another. Close the app normally.
- [ ] N2. Reopen the app. **Expected:** the demo data is back, and your new task and edits are gone. Phase 1 has no storage.
- [ ] N3. Record the result.

### O. Clean-machine check
- [ ] O1. Run the checklist on a Windows machine that has never run Nexora or Flutter. Note any Windows security prompt or SmartScreen warning.

---

## 9. Known limitations and open items

### Known limitations (by design in Phase 1)
- **No persistence.** All data is in memory. Every restart returns to the demo data. Changes are lost on exit. (Phase 2 adds SQLite.)
- **No delete.** Tasks cannot be removed in Phase 1.
- **No moves.** A task cannot be moved to another parent or project.
- **No light theme.** Dark only (decision 7).
- **Desktop only.** Below 900 px the app shows a notice and no editor. Windows is the only target.
- **Keyboard scope.** The keymap covers the list and the editor only. The sidebar is not in the keymap. Ctrl is the command key; there is no Cmd binding.
- **No notifications, tray or reminders.** These are Phase 4.
- **Test font.** Golden tests use Flutter's built-in test font. Real typography is checked manually (section 8, M4).

### Deviations and open owner decisions
- **Specification 5.4 item 4 (Discard after a failed create):** the owner approved transactional behaviour on 2026-11-12. The Discard choice is committed only after the pending create succeeds. This is now the specification, recorded in the plan document, Section 5.4 item 4. It is covered by `task_workspace_transaction_test.dart`.
- **Esc in the search box:** the specification (section 5.2) says Esc **clears** the query. The implementation returns focus to the list and leaves the query. **Open: the owner must decide which behaviour Phase 1 should use.** Until then, the implemented behaviour is what the automated tests check.
- **Golden baselines** are regenerated only on the pinned runner. Changing the Flutter version or the runner image requires regenerating them.

### Open items outside Phase 1
- PR #1 (Phase 0 documentation) remains open as a Draft. It is not part of Phase 1. The owner should close it or keep it.
- The Draft PRs #5 to #10 are superseded by PR #11 for the final verification. The owner may close them after acceptance, or keep them as the record of stacked review. Nothing has been merged into `main`.

### Unresolved defects
- None known that block acceptance. Each defect found during the work is listed in section 3 and was fixed before the final head.
- Not independently reviewed yet. An independent review of the final integrated branch is a separate step before the Live Acceptance handoff.

---

## 10. Reproduction instructions (for anyone rebuilding)

The owner does not need Flutter. CI builds and tests the app. To reproduce the final evidence:

```bash
git fetch origin
git checkout 3be43876f5          # or: git checkout feature/phase-1-golden
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
pwsh ./tool/package_windows.ps1 -OutputDir ./dist
```

Run the first six commands on Windows with Flutter 3.47.9 and Dart 3.13.7 for the same results. Golden comparisons are valid only on the pinned Windows environment.

No secrets, service-role keys, Supabase credentials or environment files are needed or used. The app makes no network calls.

---

## 11. Attestation boundaries

- Automated gates are green on the final code head. That is the only verification claimed here.
- Manual Live Acceptance has **not** been performed. Its pass or fail is the owner's decision, recorded in section 8.
- Nothing has been merged into `main`. No production change, Supabase write, migration, deployment or Phase 2 work was made.
