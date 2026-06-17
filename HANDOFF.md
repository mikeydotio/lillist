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

## Done — Wave 4: macOS hosting + retirement ✅ (app builds, unit tests green)

- `QuickCapturePanelController` rewritten: hosts `TaskEditorView` in the
  non-activating floating `NSPanel`; `toggle()` = quick draft (no-op while
  open), `open(taskID:)` = existing full (re-targets while open). Resizes
  quick↔full via `withObservationTracking` on `model.mode` (top-pinned grow).
  **Resign-key auto-dismiss removed** (status Menu popover / app-switch no
  longer nuke it); close is explicit (Done / Esc via `onExitCommand` / cancel).
  Attachment add → `NSOpenPanel`. Posts `.lillistTasksDidChange` on close.
- `EditorOpenDecision` (new, pure: present/retarget/noop) + 4 unit tests.
- `OpenTaskEditorAction` env key (new) injected by `LillistApp` → panel.open.
- `RootSplitView` 3→2 col (`detail:` = task list; `contentColumn`/`splitView`
  extracted so `body` type-checks); `taskSelection` is now list highlight;
  observes `.lillistOpenTaskEditor` → opens selection. `.detail` focus removed.
- `TaskListView`: row `.onTapGesture` → `openTaskEditorAction(id)`; observes
  `.lillistTasksDidChange` → refresh.
- `LillistCommands`: "Focus Detail" ⌘3 removed; "Open Task" (Return,
  list-gated) added. `CommandNotifications`: `.lillistFocusDetail` →
  `.lillistOpenTaskEditor` (+ `.lillistTasksDidChange`); guard test + observed
  set updated. `FocusedListColumn`: `.detail` removed (gating test → 2 cases).
- Retired macOS `Views/Detail/*` + `Views/EmptyView/NoSelectionDetailView`;
  `Apps/project.yml` co-compiles `EditorOpenDecision` into the test bundle;
  macOS project regenerated (pbxproj idempotent).
- ⚠️ **macOS glass is manual-verify only** (no snapshot path). Mikey must
  eyeball: hotkey quick capture floats over another app (Lillist not
  activated); "…" grows the panel; single-click a row opens full; ↑/↓ move
  highlight without opening, Return opens; the status Menu does NOT dismiss
  the editor; resize; attachment NSOpenPanel; detail column gone; ⌘N inline
  create still works. (Run macOS unit tests with `GENERATE_INFOPLIST_FILE=YES`.)
- ⚠️ **Keymap call:** Return opens; **Space stays "Toggle Started"** (kept the
  loved status fast-path rather than rebinding it to open). Adjust if you want
  Space to open too.

## Next — Wave 5 (see plan)

- **W5 polish:** Reduce-Motion, discard/undo toasts, `lastCommitWarning` UI,
  localization sync across all three `Localizable.xcstrings`, delete folded-away
  quick-capture files + migrate baselines.

## Notes
- SourceKit "No such module 'LillistCore'/'Testing'" warnings on the new files
  are cross-package indexing artifacts — `swift build`/`swift test` resolve fine.
- Nothing committed yet (commit when Mikey asks). Branch is clean off `main`.
