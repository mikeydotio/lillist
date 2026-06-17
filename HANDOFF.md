# HANDOFF — Unified Task Editor

Branch: `feat/unified-task-editor`. Full spec: the approved plan at
`~/.claude/plans/next-tapping-on-a-cozy-eclipse.md` (Context + locked decisions
+ architecture + 5 waves + verification). This file tracks live state only.

## Done — Wave 1: Core + model foundation ✅ (all green)

- **`TaskStore.isCommittableTitle(_:)`** — public `nonisolated static`; the
  single source of truth for the non-empty-after-trim rule (`validateTitle`
  now delegates to it). `Packages/LillistCore/.../Stores/TaskStore.swift`.
  Test: `TaskStoreCRUDTests.committableTitle`.
- **macOS `attachmentStore`** wired into `Apps/Lillist-macOS/Sources/AppEnvironment.swift`
  (declared, init'd, breadcrumbs hooked) — parity with iOS so the editor's
  attachment section works cross-platform. ⚠️ macOS app build not yet
  re-run (additive, low-risk) — confirm in Wave 4's macOS xcodebuild.
- **`TaskEditorModel`** + `TaskEditorMode`/`TaskEditorPresentation`/`TaskEditorError`
  in `Packages/LillistUI/Sources/LillistUI/Editor/`. `@MainActor @Observable`,
  injected with a `Stores` value bundle (LillistUI stays `AppEnvironment`-free).
  Phase machine (`draft`/`promoting`/`live(UUID)`/`abandoned`), serialized
  `ensureLive()` auto-promote, create-then-best-effort `runCommit` with
  `lastCommitWarning`, draft tag-name buffering, live-save (debounced text via
  `saveTextNow`; immediate `saveScalarsNow`/`setStatus`), discard→softDelete.
  Tests: `Tests/LillistUITests/Editor/TaskEditorModelTests.swift` (19, all pass).

Verify Wave 1:
```bash
swift test --package-path Packages/LillistUI --filter TaskEditorModel
swift test --package-path Packages/LillistCore --filter committableTitle --parallel --num-workers 2
```

## Refinement to carry into Wave 2 (improves on the plan)

The plan assumed the shared editor would take **injected ViewBuilder closures**
for notes/subtasks/journal/followUp because those components were
`AppEnvironment`-coupled. Now that `TaskEditorModel` owns the stores and every
mutation (`addSubtask`, `addJournalNote`, `addReminder`, `addTag`,
`commitRecurrence`, `saveTextNow`, …) + exposes the loaded collections
(`subtasks`, `journal`, `reminders`, `assignedTags`, …), `TaskEditorView` can
render those sections **natively through the model** — no injection, less
platform-forked code, truer "one shared editor". Keep an injection/closure seam
ONLY for genuinely platform-specific bits: attachment acquisition
(`PhotosPicker` on iOS / `NSOpenPanel` on macOS) and subtask-open navigation
(host re-targets the singleton editor). LillistUI stays `AppEnvironment`-free
because everything routes through the model.

## Next — Wave 2: Shared editor view + net-new components

In `Packages/LillistUI/Sources/LillistUI/Editor/`:
- **`TaskEditorView`** — pure presenter, `@Bindable model`. Quick mode = title
  field + token chips (fold in `iOS/QuickCaptureDialog` body). Full mode =
  ScrollView of sections rendered natively via the model: title, status
  (reuse `StatusIndicatorView`/`StatusGlyph`), dates (+hasTime toggles), pin
  (`RainbowToggleStyle`), tags (`TagAssignmentField`), recurrence (row →
  reuse `RecurrenceEditorView`), reminders (`ReminderEditorSection`), notes
  (debounced TextEditor), subtasks list (`TaskRowView` + add field), journal
  list, attachments (injected acquisition). Use `GlassSurface` `.panel`,
  `LillistMotion`/`LillistSpacing`/`LillistRadius`/`LillistTypography`.
- **`TagAssignmentField`** (net-new) — removable `TagChipView` chips + add/create
  field over `tagStore.children(of:)`; calls `model.addTag/removeTag`. Tag
  filter/dedupe as `nonisolated static` helpers.
- **`ReminderEditorSection`** (net-new) — `NotificationKind` picker + offset/
  fire-date; lists `model.reminders`; calls `model.addReminder/deleteReminder`.
- Offscreen unit/snapshot tests for sub-components WITHOUT a status `Menu`
  (dates, token row, tag field). Assembled editor snapshots are app-hosted in
  Wave 3 (the status `Menu` blanks offscreen captures — see plan Testing).

Build/verify: `swift build --package-path Packages/LillistUI` (strict
concurrency + warnings-as-errors), plus `swift test --package-path Packages/LillistUI --filter <name>`.

## Then — Waves 3–5 (see plan)

- **W3 iOS hosting + retirement:** `TaskEditorHost` (replaces
  `QuickCaptureDialogHost`), generalize `QuickCaptureDialogPresenter`, reroute
  3 open sites (`TasksScreen` NavigationLink→Button `onOpenTask`,
  `TaskSubtasksTab`, `RootShell` collapse), delete iOS `Detail/TaskDetailView`.
  App-hosted quick+full snapshots; re-verify the tour. Signed `xcodebuild test
  -scheme Lillist-iOS`; regenerate baselines via `RECORD_SNAPSHOTS=YES`.
- **W4 macOS hosting + retirement:** extend `QuickCapturePanelController`
  (resizable quick↔full, grow, singleton across hotkey/⌘N/`.lillistNewTask`,
  **remove resign-key auto-dismiss** so the status menu popover + app-switching
  don't nuke the editor), `EditorOpenDecision` helper, single-click open +
  ↑/↓ keyboard-nav (Return/Space open), retire detail column
  (`RootSplitView` 3→2 col, `LillistCommands` drop ⌘3, `CommandNotifications`
  remove `.lillistFocusDetail`/add `.lillistOpenTaskEditor`, `FocusedListColumn`
  drop `.detail`). `xcodegen generate` both projects; manual macOS glass verify.
- **W5 polish:** Reduce-Motion, discard/undo toasts, `lastCommitWarning` UI,
  localization sync across all three `Localizable.xcstrings`, delete folded-away
  quick-capture files + migrate baselines.

## Notes
- SourceKit "No such module 'LillistCore'/'Testing'" warnings on the new files
  are cross-package indexing artifacts — `swift build`/`swift test` resolve fine.
- Nothing committed yet (commit when Mikey asks). Branch is clean off `main`.
