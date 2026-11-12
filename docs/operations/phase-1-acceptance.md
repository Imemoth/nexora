# Phase 1 — Live Acceptance Package

Status: **Phase 1 functionally accepted by the owner (2026-11-12). Integrated into `main` through PR #12 by merge commit.** Automated gates are green on the final code head `64d10cb`. The owner made the acceptance decision. The agent did not run the manual checks in section 8, and this document does not tick them.

Scope: a fully offline, in-memory Windows desktop prototype with deterministic demo data. Phase 1 has **no durable storage**. Nothing is saved between runs, and no SQLite, Supabase, network or authentication code exists in the app. Persistence (SAVE-PERSIST-01) is explicitly out of Phase 1 scope and is completed in Phase 2A.

---

## 1. Final integrated code head

| Item | Value |
|---|---|
| Repository | `Imemoth/nexora` |
| Final code head (tested) | `64d10cb25ed3e6c6180ec38b63b5191dd1da8b44` on branch `feature/phase-1-acceptance` (PR #12) |
| Final CI run (code head) | [43198018450](https://github.com/Imemoth/nexora/actions/runs/43198018450) — **success** (every step, including format, analyze, 270 tests, release build, portable ZIP and smoke test) |
| This document's commit | a documentation-only commit on top of `64d10cb`. It changes no code. Its own CI run is recorded in PR #12. |
| Toolchain | Flutter 3.47.9 (stable), Dart 3.13.7, `windows-latest` GitHub Actions runner |

The code head contains every Phase 1 task (2 through 8), the fixes from the independent final review (section 9), and the owner's two-stage Esc decision (`5ba668a`, with its red test `02ffe79`). Every stacked PR head in section 2 is a verified ancestor of it.

Earlier verified heads are kept for traceability: `3be43876f5` (the first full green run, section 3), `682378e18c` (the previous code head, CI run 43193981389, before the Esc decision), and the review-fix heads listed in section 2.

---

## 2. Implementation PRs and dependency order

Execution order was strictly linear during review. Each PR's base was the PR above it. All were Draft during review. On integration, PR #12 was retargeted to `main` and merged by merge commit (section 12), and PRs #5 to #11 were closed as superseded.

| Order | PR | Task | Branch | Head at last CI | CI run | Base |
|---|---|---|---|---|---|---|
| 0 | [#4](https://github.com/Imemoth/nexora/pull/4) | Task 1: pure domain | `feature/phase-1-domain` | `b746db8` | 43105602655 | `main` — **merged** into `main` at `c1c1557` before Phase 1 implementation (owner's merge) |
| 1 | [#5](https://github.com/Imemoth/nexora/pull/5) | Task 2: application workspace | `feature/phase-1-application` | `ee56e7a` | 43169699581 | `main` |
| 2 | [#6](https://github.com/Imemoth/nexora/pull/6) | Task 3: shell and sidebar | `feature/phase-1-shell` | `86b5c7d` | 43172667316 | #5 |
| 3 | [#7](https://github.com/Imemoth/nexora/pull/7) | Task 4: task tree, search, sort | `feature/phase-1-tree` | `22ab5ce` | 43173864694 | #6 |
| 4 | [#8](https://github.com/Imemoth/nexora/pull/8) | Task 5: editor, creation, unsaved-change gate, exit gate, transactional discard | `feature/phase-1-editor` | `bde6f5d` | 43193685246 | #7 |
| 5 | [#9](https://github.com/Imemoth/nexora/pull/9) | Task 7: responsive overlay, palette, accessibility | `feature/phase-1-responsive-lead` | `14dae11` | 43193959909 | #8 |
| 6 | [#10](https://github.com/Imemoth/nexora/pull/10) | Tasks 6+7 integration (keyboard merged in) | `feature/phase-1-integration` | `b591545` | 43193967641 | #9 |
| 7 | [#11](https://github.com/Imemoth/nexora/pull/11) | Task 8: golden tests and baselines | `feature/phase-1-golden` | `ee4c284` | 43193975795 | #10 |
| 8 | [#12](https://github.com/Imemoth/nexora/pull/12) | Task 9: acceptance package and full Phase 1 integration (this document) | `feature/phase-1-acceptance` | `64d10cb` (code) + docs commit | 43198018450 (code) | `main` (retargeted from #11 at integration) |

Notes on the stack:
- Task 6 (keyboard) was developed on `feature/phase-1-keyboard` and merged into the integration branch. It has no separate PR, to avoid running CI twice on the same code.
- PRs #5 to #11 were Drafts superseded by PR #12. Their heads are verified ancestors of `64d10cb`. They are closed as superseded at integration, and their branches are kept.
- PR #1 (`docs/phase-0-implementation-plan`, a Phase 0 documentation PR) is still open as a Draft. It is not part of Phase 1.

---

## 3. CI results

All gates ran on `windows-latest` with the pinned toolchain. Results for the final code head `64d10cb` (run 43198018450):

| Gate | Result |
|---|---|
| Flutter and Dart version verification | pass (Flutter 3.47.9; Dart 3.13.7) |
| Dependency resolution (`flutter pub get`) | pass |
| Dart formatting (`dart format --set-exit-if-changed`) | pass |
| Analyzer (`flutter analyze`) | pass — "No issues found!" |
| Full real Flutter test suite (`flutter test`) | pass — **270 tests passed**, including architecture, domain, application, widget, keyboard, accessibility, responsive and golden tests |
| Windows release build (`flutter build windows --release`) | pass |
| Portable ZIP packaging (`tool/package_windows.ps1`) | pass — "PACKAGE PASS" |
| Unicode and spaces path smoke test | pass — launched from `…\nexora smoke é测试 59561120`, closed cleanly, exit 0 |
| Artifact upload | pass |

The previous code head `682378e` (run 43193981389, 266 tests) passed the same gates before the owner's Esc decision. The Esc change adds tests and raises the count to 270. An earlier full green run on `3be43876f5` (run 43188559503, 262 tests) passed the same gates before the independent final review. Its artifact is superseded by the one in section 6.

### Repair history (for traceability)

Each item below was fixed with a regression test or a lint correction. None is open.

- Owner decision: two-stage Esc in the search field. Red test `02ffe79`, fix `5ba668a`. Intermediate CI runs on those commits were cancelled by the concurrency rule. The final heads `9e0bc0e` and `64d10cb` ran green.
- Task 5: analyzer errors on `AppExitResponse`/`AppExitType` (defined in `dart:ui` at this Flutter version) — `10e532a`.
- Task 5: 22 widget tests broken by an 88 px overflow in the editor action row — `aed8cfd`.
- Task 5: text-finder ambiguity (indicator and dialog title both "Unsaved changes") — `3bff274`.
- Task 6/7: duplicate "New task" text in a keyboard test; redundant imports — `622cf0e`, `2ce9f6c`.
- Task 8: the golden generator stalled because a piped `flutter --version | head` closed the Flutter tool's output pipe, which made the tool retry forever — `d6ef667`.
- Final review: keyboard dead after closing the overlay (blocking) — `22781d9`; revert during a save (major) — `bde6f5d`; no focus on the title after a create (major) — `f2ee8df`; failed load shown as empty (minor) and the strings rule missing double quotes (minor) — `682378e` lineage. Each has a red test commit before its fix.

---

## 4. Test counts

| Source | Count | Status |
|---|---|---|
| Real `flutter test` on the final code head `64d10cb` (CI run 43198018450) | **270 passed** (CI log: "270 tests passed.") | official |
| Real `flutter test` on the previous code head `682378e` (CI run 43193981389) | 266 passed, 0 failed | superseded by the final head |
| Real `flutter test` on the earlier full green run (CI run 43188559503, `3be4387`) | 262 passed, 0 failed | superseded, kept for history |

Local checks used a stand-in for `flutter_test` that cannot run widget tests. Those local counts are not evidence and are not reported here. CI is the only official test run.

### What the automated tests cover

- **Domain** (Task 1): parent-change rules, creation rules, title validation, calendar dates, smart views, ordering, search, completion summaries.
- **Application** (Tasks 2 and 5): workspace state, the unsaved-change gate for every transition in the plan's table, failed-save and failed-create invariants, the transactional Discard decision, duplicate and concurrent operation guards (including refused revert during a save), the reveal rule for new tasks, exit gating.
- **Architecture**: no Flutter import in core, domain or application; no SQLite, Supabase or HTTP package anywhere in `lib/`; no visible-text literals (single- or double-quoted) outside `AppStrings`.
- **Widget** (Tasks 3 to 7): shell layout, sidebar counts, task tree (expand/collapse, done/total, Ready for review), search, sort, empty states, the editor (Save/Revert enabled only when dirty, validation, failed-save message), creation dialogs and focus after create, the unsaved-change dialog, exit flows, keyboard shortcuts with focus restoration (including after the overlay closes at 1000 px), responsive breakpoints (overlay, desktop-only notice), text scale 1.3 without overflow, tooltips and 40 px hit targets, a failed load shown as an error.
- **Contrast** (Task 7, pure Dart): every text token against every surface, 4.5:1 normal text and 3:1 large text. The lowest pair is `textMuted` on `surface2` at **5.14:1**.
- **Golden** (Task 8): two pixel comparisons on the pinned runner (section 5).

---

## 5. Golden baselines

| File | Scenario |
|---|---|
| `test/golden/goldens/all_view_selected.png` | All view at 1280×800 with one task selected |
| `test/golden/goldens/empty_state.png` | Empty state ("No tasks here yet") at 1280×800 |

- Generated on `windows-latest` with Flutter 3.47.9 by a temporary push-triggered workflow (run 43185260570, commit `d6ef667`). The workflow was removed in the commit that added the baselines.
- The final code head's golden test compares against these committed files and passed (section 3). The golden files are unchanged since `682378e`.
- Demo data is fixed to the date the test runs for (`testToday`), so the output is deterministic. Test font rendering uses Flutter's built-in test font, which draws glyphs as blocks. **The goldens therefore prove layout, colour and structure, not the final typeface.** The real Windows font is a manual check (section 8).
- The goldens were checked by eye after generation: the selected row is highlighted, and the empty state shows its message.

---

## 6. Artifact metadata

| Item | Value |
|---|---|
| Artifact name (GitHub) | `nexora-windows-portable` |
| Artifact ID | `13934960271` |
| Produced by | run [43198018450](https://github.com/Imemoth/nexora/actions/runs/43198018450), code head `64d10cb` |
| Download (owner) | GitHub Actions run page → Artifacts → `nexora-windows-portable`. Or: `gh run download 43198018450 --repo Imemoth/nexora --name nexora-windows-portable` |
| Outer artifact size | 12,005,259 bytes |
| **Outer artifact SHA-256** (GitHub container; matches the API digest `sha256:7a890b89…`) | `7a890b89c027ddca0ef357ac1cce462f322a72429ebe833ef2a001d9300bf566` |
| Inner application ZIP name | `nexora-windows-portable.zip` |
| Inner application ZIP size | 12,011,958 bytes |
| **Inner application ZIP SHA-256** | `33df9eb553950b9f8b63dbd258b13888691ebe13803ac2ec9f0a9206e12daedc` |
| Inner ZIP integrity | `unzip -t`: no errors detected |
| Inner ZIP entries | 14 (listed below) |
| Superseded artifact (code head `682378e`, run 43193981389) | ID `13931254888`; outer `f999775e4b704ef68654ae9d3ede2da3b4979b648e703d312d0cd1fb30ab0a57`; inner `8d00f26a90813bcc94e9a137f819d74d95933ced1f7fcf4015106b12a1334b24`. Kept for traceability only. |

### Verification steps (owner)

```bash
# 1. Outer container (the GitHub artifact, as downloaded from the API)
sha256sum nexora-windows-portable-outer.zip   # expect 7a890b89…f566

# 2. Inner application ZIP
sha256sum nexora-windows-portable.zip         # expect 33df9eb5…daed
unzip -tq nexora-windows-portable.zip         # expect "No errors detected"
unzip -Z1 nexora-windows-portable.zip | wc -l # expect 14
```

PowerShell equivalent: `Get-FileHash -Algorithm SHA256 <file>`.

Note: `gh run download` extracts the artifact, so the file it writes is the inner application ZIP, not the outer container. To hash the outer container, fetch it with `gh api repos/Imemoth/nexora/actions/artifacts/13934960271/zip`.

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

Twelve file entries plus two directory entries (`data/flutter_assets/packages/` and `packages/cupertino_icons/`) make the 14 that the ZIP reports.

### Smoke test evidence (from CI log)

- `OK: ZIP contains 14 entries including all required runtime files`
- `OK: release bundle complete`
- `SMOKE PASS: launched from 'C:\Users\runneradmin\AppData\Local\Temp\nexora smoke é测试 59561120', closed cleanly (exit 0)`
- `PACKAGE PASS: D:\a\nexora\nexora\dist\nexora-windows-portable.zip`

---

## 7. Feature inventory (what the prototype does)

### Navigation and layout
- Three panes at 1100 px and wider: sidebar (240 px), task list, details editor (360 px).
- 900 to 1099 px: the details editor becomes an overlay over the list while a task is selected. Closing it goes through the same unsaved-change gate as selection. Focus then returns to the list, and the keyboard keeps working.
- Below 900 px: a desktop-only notice shows; the list stays usable; no overlay opens.
- Sidebar: Today, Next 7 Days, Overdue, All, and a Projects section. Each entry shows a live count that ignores the search query.
- The default view is All.

### Task tree and list
- Recursive hierarchy with expand/collapse. Children appear only under expanded parents.
- Each row shows: indentation by depth, status (text), due date (ISO), priority (text), and done/total for parents.
- A parent whose children are all done shows **Ready for review**. Its status is never changed automatically.
- Search over title and notes, case-insensitive. The result count includes children hidden under collapsed parents.
- Sort: position, due date, priority, title. Sorting changes only the display order.
- Empty states: no matches (with a Clear action), empty project, empty smart view. A failed load shows the load-error message.
- If a collapse hides the selected task, the list says: "Selected task is hidden in this view."

### Editing
- Title, status, priority, date-only due date (picker and clear), and plain-text notes.
- Save and Revert are enabled only for a dirty draft. An "Edited, not saved" indicator shows while the draft is dirty.
- Validation: an empty or over-200-character title is refused, and nothing is saved.
- Save failures keep the edits and show an error message.
- Revert is refused while a save or transition is running.
- Add subtask is disabled for an archived draft.

### Creation
- New task (root) in a project, with a project selector.
- Subtask under a non-archived task. It expands the parent and selects the child.
- After a create, the details title takes focus, on every route (New task button, Ctrl+N, Ctrl+Shift+N, Add subtask).
- An undated task is hidden in Today, Next 7 Days and Overdue. Creating one from those views moves the selection to its project and clears a search that hides it. The task never receives a due date.

### Unsaved changes (the gate)
- Selecting another task, changing view, project or search, clearing selection, creating, and exiting all pass through one gate when the draft is dirty. Sorting and expanding do not.
- The dialog offers Save, Discard and Cancel. A failed save keeps the dialog open with the error. The dialog cannot be dismissed by tapping outside it or by Esc.
- **Discard (owner-approved behaviour, 2026-11-12):** Discard is committed only when the pending transition succeeds. If a pending create fails after Discard, the dirty draft, the selection and the pending create are all kept, and the error is shown. The user can retry or cancel, and cancel keeps every edit.
- Duplicate and concurrent operations are refused: a second Save, Discard, create or revert while one is running is not executed.

### Exit
- Closing the app with a dirty draft opens the same dialog and cancels the exit. Save or Discard then exits.
- A failed save during exit does not exit.

### Keyboard (Ctrl is the command key; no Cmd binding)

| Key | Action |
|---|---|
| Up / Down | Move selection through visible rows (through the gate) |
| Right / Left | Expand or collapse; Left moves to the parent when collapsed |
| Enter | Focus the title field of the selected task |
| Esc | Two-stage in the search field: a non-empty query is cleared first and focus stays in the field; a second Esc, or Esc with an empty query, returns focus to the list. In the details editor, returns focus to the list. In the list, clears the selection through the unsaved-change gate. Esc never dismisses the unsaved-change dialog (owner decision, Phase 1 final). |
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

**Owner record.** The owner decided on 2026-11-12 that Phase 1 is functionally accepted. The checkboxes below are the owner's record. This document does not tick any item, because per-item results were not supplied to the agent. The owner should record which build the manual checks ran against: the previous head `682378e` (artifact `13931254888`) or the final head `64d10cb` (artifact `13934960271`, section 6). The Esc items L12 to L14 cover the final-head behaviour only if they were run on the final build.

Run the artifact from section 6 on a Windows 10 x64 machine (or Windows 11). Record a pass or fail and a short note for each item. Use a path with spaces and a non-ASCII character to extract the ZIP, to match the automated smoke test.

Note on demo data: the demo data is built from the **date the app is launched**. Counts for Today, Overdue and Next 7 Days therefore depend on the day you run it. The checks below use relative wording for that reason.

### A. Setup
- [ ] A1. Verify the outer and inner SHA-256 values in section 6. Record the values you computed.
- [ ] A2. Extract the inner ZIP to a folder whose path contains a space and a non-ASCII character. Confirm all 14 entries exist.
- [ ] A3. Confirm no installer or admin rights are needed.

### B. Launch and exit
- [ ] B1. Double-click `nexora.exe`. The window opens with the dark theme. The in-app name is "Nexora". The Windows window title and taskbar label come from the native runner and read `nexora`; record what you see.
- [ ] B2. The default view is All, and the sidebar shows Today, Next 7 Days, Overdue, All and Projects (Home, Work).
- [ ] B3. Close the window with the close button. The app exits. The process is gone from Task Manager.
- [ ] B4. Close the window while a draft is dirty (see J). The dialog appears and the app does not close.

### C. Layout
- [ ] C1. At full width (at least 1100 px) the sidebar, list and details editor show side by side.
- [ ] C2. Resize the window to between 900 and 1099 px. Select a task. The editor appears as an overlay on the right. Close it with its × button.
- [ ] C3. Resize to below 900 px. The desktop-only notice shows. The list still works. No overlay opens.
- [ ] C4. Set the Windows display scale to 125% and then 150%. Nothing is cut off, and the buttons still show their text.

### D. Smart views and projects
- [ ] D1. Today shows the task "Plan weekend groceries" as due on the launch date. Its count is 1.
- [ ] D2. Overdue shows "Pay utility bill" and "Reply to client email". Next 7 Days shows "Renew car insurance" and "Quarterly review". Confirm these match the launch date.
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
- [ ] F6. After a successful create, the details title field has keyboard focus. Type a character and confirm it goes into the title.

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
- [ ] H8. Tap outside the dialog and press Esc. The dialog stays open.

### I. Failed-save behaviour (Discard exception)
- [ ] I1. The app cannot be forced to fail a save from the UI, so this item is covered by automated tests (`task_workspace_transaction_test.dart`, `editor_test.dart`). Owner: confirm you accept this as evidence, or request a manual fault-injection build.
- [ ] I2. Confirm the Discard exception described in section 7 matches what you expect.

### J. Exit protection
- [ ] J1. With a dirty draft, click the window close button. The dialog appears and the app stays open.
- [ ] J2. In the dialog, click Save. The app closes after saving. Restart and confirm the change is **not** there (no durable storage, see section 9).
- [ ] J3. Repeat with Discard. The app closes without saving.
- [ ] J4. Repeat with Cancel. The app stays open and the edit is kept.
- [ ] J5. Click the close button several times quickly with a dirty draft. Only one dialog is open.
- [ ] J6. Alt+F4 behaves like the close button (J1 to J4). Record the result.

### K. Search and sort
- [ ] K1. Click the search box and type "bike". Only "Repair bike" shows. The count is "1 task".
- [ ] K2. Type "zzzz". "No tasks match your search" appears with a Clear button. Click Clear. All tasks return.
- [ ] K3. Search matches notes too: type "offers". The task "Renew car insurance" shows.
- [ ] K4. Open the sort menu. Choose Due date. Dated tasks come first, earliest first. Choose Title. The list is alphabetical.

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
- [ ] L10. Open the overlay at 1000 px, close it with its × button, and press Down. The selection moves.
- [ ] L11. Complete flows L5, L6 and L7 without touching the mouse.
- [ ] L12. Press Ctrl+F and type "bike". Press Esc once: the query clears and the search box still has focus. Press Esc again: focus moves to the task list.
- [ ] L13. Select a task and edit its title. Press Ctrl+F, type "alp", then Esc. The query clears, the edit is still there, and the task is still selected. No dialog appears.
- [ ] L14. With a dirty draft, click another task so the unsaved-change dialog appears. Press Esc. The dialog stays open. Use Cancel, Save or Discard to answer it.

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

## 9. Independent final review and known limitations

### Independent final review
An independent reviewer (a fresh agent that did not implement the code) audited the integrated branch at `3be4387` against the specification and checked the claims in this document against the repository and CI. Its blocking and major findings were fixed before the code head in section 1, each with a red test first:

- **Blocking — keyboard dead after the overlay closed** (900–1099 px). Fixed in `22781d9`; test: keyboard navigation after the overlay closes at 1000 px.
- **Major — revert during a save** could leave a saved draft dirty against the wrong base. Fixed in `bde6f5d`; test: revert is refused during a save.
- **Major — no focus on the details title after a create** (spec 5.5). Fixed in `f2ee8df`; test: a successful create focuses the title. One helper now serves every create entry point.
- **Minor — a failed load showed an empty list** without saying so. Fixed; test: the load-error message shows.
- **Minor — the strings rule only matched single quotes.** Fixed; the rule now matches double quotes too.
- **Document claims** were corrected in this version (section 11 lists what changed).

### Known limitations (by design in Phase 1)
- **No persistence (SAVE-PERSIST-01).** All data is in memory. Every restart returns to the demo data, and changes are lost on exit. This is explicitly out of Phase 1 scope. It is completed in Phase 2A (local SQLite persistence, branch `feature/phase-2a-sqlite`). Owner decision: accepted as a Phase 1 limitation.
- **No delete.** Tasks cannot be removed in Phase 1.
- **No moves.** A task cannot be moved to another parent or project.
- **No light theme.** Dark only (decision 7).
- **Desktop only.** Below 900 px the app shows a notice and no editor. Windows is the only target.
- **No notifications, tray or reminders.** These are Phase 4.
- **Test font.** Golden tests use Flutter's built-in test font. Real typography is checked manually (section 8, M4).
- **Demo data date.** The demo data is relative to the launch date, so the Today, Overdue and Next 7 Days contents change from day to day.

### Deviations recorded but not fixed (owner review requested)
These differ from the wording of the specification or are design gaps the review found. None blocks Live Acceptance on its own, but each should be accepted or changed by the owner.

- **Esc in the search box:** resolved by the owner's final decision. A non-empty query is cleared first, focus stays in the field, and a second Esc returns focus to the list. Recorded in the approved keymap (plan section 6.1) and tested by `keyboard_test.dart`.
- **Right and Left are gated** by the unsaved-change dialog when a draft is dirty. Specification 6.1 marks them as ungated. Right on an expanded parent moves focus to its first child, which the specification does not describe.
- **Cancelling a gated create drops the title typed in the create dialog.** The create is held as a pending transition until the gate resolves. Cancel discards it. The existing draft is kept.
- **Up and Down are consumed in the search box**, so the caret cannot move with them there.
- **Cancel and Discard are ignored silently while a save is running.** The dialog gives no message. This is the duplicate-operation guard working as designed; the message is a gap.
- **Border colour contrast.** The border token used for input outlines is about 1.5 to 1.9:1 against the surfaces. WCAG 1.4.11 (non-text contrast) asks for 3:1 where the boundary is needed to identify a control. The specification does not set a non-text requirement; the contrast test covers text tokens only. Dialog surfaces use Material 3 defaults and are not checked against the palette.
- **Exit listener placement.** The exit request is handled by the unsaved-change host (`unsaved_changes_host.dart`), not in the application root as specification 5.2 describes. Behaviour is the same, and the native close path itself is covered by manual check J.

### Unresolved defects
- None known that block acceptance. The deviations above are recorded for the owner to accept or change.
- A second independent review of the final head is not performed. The review that was performed covered the code at `3be4387`. The fixes listed above were made after it and are covered by CI on the final head `64d10cb`. The owner's Esc decision (`5ba668a`) was made after the review, and it is covered by the same CI run.

### Open items outside Phase 1
- PR #1 (Phase 0 documentation) remains open as a Draft. It is not part of Phase 1. It is left unchanged pending a separate owner decision.
- PRs #5 to #11 are superseded by PR #12. They are closed as superseded at integration (section 12). Their branches are kept.

---

## 10. Reproduction instructions (for anyone rebuilding)

The owner does not need Flutter. CI builds and tests the app. To reproduce the final evidence:

```bash
git fetch origin
git checkout 64d10cb25ed3e6c6180ec38b63b5191dd1da8b44
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build windows --release
pwsh ./tool/package_windows.ps1 -OutputDir ./dist
```

Run these on Windows with Flutter 3.47.9 and Dart 3.13.7 for the same results. Golden comparisons are valid only on the pinned Windows environment.

No secrets, service-role keys, Supabase credentials or environment files are needed or used. The app makes no network calls.

---

## 11. Attestation boundaries and changes in this version

- Automated gates are green on the final code head `64d10cb` (section 3). That is the only verification claimed by the agent.
- Owner decision (2026-11-12): Phase 1 is functionally accepted. The manual checks in section 8 were the owner's to run. The agent did not perform them.
- Phase 1 is integrated into `main` through PR #12 by merge commit, as the owner authorized on 2026-11-12 (section 12). PR #4 (Task 1, the pure domain) was merged into `main` earlier, at `c1c1557`.
- No production change, Supabase write, migration, deployment or Phase 2 work was made.

Changes in this version (2026-11-12, owner acceptance and integration):
- Status changed from "prepared, not accepted" to owner-accepted functional Phase 1.
- Final code head `64d10cb`: CI run 43198018450, 270 tests, artifact `13934960271` with verified digests (sections 1, 3, 4 and 6).
- SAVE-PERSIST-01 recorded as out of Phase 1 scope and completed in Phase 2A (scope line and section 9).
- Section 12 added: the integration record.

Earlier changes, against the previous draft, after the independent review:
- The code head, PR heads, CI run, test count (266), artifact ID, checksums and smoke-test path were updated to the final run.
- The statement that nothing had been merged into `main` was corrected (PR #4 is merged).
- The demo-data description was corrected: the data is built from the launch date, not the build date.
- The window-title expectation was corrected: the Windows title comes from the native runner, not from the in-app name.
- The unverified local test count was removed. The contrast figure was corrected to 5.14:1.
- The deviations found by the review were recorded in section 9, and the fixed defects were listed with their commits.

---

## 12. Integration record

| Item | Value |
|---|---|
| Integration PR | [#12](https://github.com/Imemoth/nexora/pull/12), `feature/phase-1-acceptance` into `main` |
| Merge method | Merge commit. No squash and no rebase, so the 74 Phase 1 commits keep their hashes. |
| Final code head before integration | `64d10cb25ed3e6c6180ec38b63b5191dd1da8b44` (CI run 43198018450, success) |
| Documentation commit | The commit that adds this section, on top of `64d10cb`. Its CI run is recorded in PR #12. |
| Superseded PRs closed | #5 to #11, after their heads were confirmed as ancestors of the integration head |
| Left unchanged | PR #1 (Phase 0 documentation). Branch `feature/phase-2a-sqlite` is not merged. |

The merge commit hash and the final `main` HEAD are recorded in PR #12 and in the git history of `main`. This document is committed before the merge, so it cannot record them.
