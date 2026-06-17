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

## Done — Wave 2: Shared editor view + components ✅ (builds clean, tests green)

In `Packages/LillistUI/Sources/LillistUI/Editor/`:
- **`TaskEditorView`** — cross-platform presenter over `@Bindable model`. Quick
  mode = capture field (`#tag ^date`) + parsed chips + Add + "…" expand
  (animated via `LillistMotion.squish`). Full mode = ScrollView of sections
  rendered natively through the model: title, status (`StatusIndicatorView`),
  dates (+ time toggles), pin, tags, recurrence (sheet → `RecurrenceEditorView`),
  reminders, notes (debounced `.task(id:)`), subtasks, journal, attachments,
  footer (Done / Delete / `lastCommitWarning`). Live-save wired via `.task`
  debounce + `.onChange(scalarKey)`. Host seams: `onOpenSubtask`,
  `onAddAttachment`.
- **`TagAssignmentField`** (net-new), **`ReminderEditorSection`** (net-new,
  pure `offsetLabel`/`describe` helpers), **`TaskEditorCollectionSections`**
  (`EditorSubtasksSection`/`EditorJournalSection`/`EditorAttachmentsSection`).
- Model gained `captureText` + `ingestCaptureText`/`isQuickCommittable`/
  `commitQuickCapture`; `expandToFull` now folds quick text into fields;
  `displayedTagNames`.
- `NotificationSpecStore.SpecRecord` got the explicit public init CLAUDE.md
  mandates (was missing).

Tests: `TaskEditorQuickCaptureTests` (4) + `ReminderFormattingTests` (2), all
green. `swift build --package-path Packages/LillistUI` clean (no warnings).
Verify: `swift test --package-path Packages/LillistUI --filter "TaskEditorQuickCaptureTests|ReminderFormattingTests"`.

## Refinement applied in Wave 2 (improves on the plan)

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

## Done — Wave 3: iOS hosting + retirement ✅ (app builds, snapshots green)

- `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift` (new) — singleton
  overlay host: `newCaptureTrigger` (FAB/⌘⇧N) → quick draft; `openTaskID` (row
  tap) → existing full; tap-outside/Esc discards a capture draft / closes an
  existing task; PhotosPicker wired to `addImageAttachment`. Replaces
  `QuickCaptureDialogHost` (deleted).
- `LillistUI/iOS/TaskEditorOverlay.swift` (new) — keyboard-aware dim-backed
  floating-card presenter (`taskEditorOverlay`).
- `TasksScreen`: `NavigationLink(value:)` → `Button { onOpenTask(id) }`
  (drag gesture preserved). New `onOpenTask` param (default no-op).
- `RootShell` collapsed `NavigationSplitView`+detail → `NavigationStack { TasksView() }`.
- `TasksView`: `TaskEditorHost` modifier + `editorStores` + `onOpenTask`.
- Retired `Apps/Lillist-iOS/Sources/Detail/*` (TaskDetailView + tabs) and
  `QuickCaptureDialogHost.swift`; iOS pbxproj regenerated.
- `ReminderEditorSection` gained `defaultDate` (new reminder seeds off the
  task's deadline/start, not "now" — better UX + deterministic snapshots).
- Snapshots: 7 `IOSScreenTourTests` task-row baselines regenerated (chevron
  removed — rows open the editor now, not push); 4 new app-hosted editor
  baselines (`test_editor_quick/full_light/dark`) in `GlassSnapshotTests`.
  `xcodebuild -scheme Lillist-iOS build` clean; both snapshot suites green.

## Next — Waves 4–5 (see plan)

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
