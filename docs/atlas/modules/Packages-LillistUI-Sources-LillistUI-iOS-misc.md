---
module: "Packages/LillistUI/Sources/LillistUI/iOS (misc)"
summary: "iOS primary-screen and overlay surfaces: TasksScreen, Quick Capture dialog, FAB, toasts, sync badge, settings shell"
read_when: "iOS Quick Capture, FAB, toasts, or screens"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ArchiveToast.swift
    blob: b914aee0fa6e5326975373f13c5e294b218fded4
  - path: Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift
    blob: d47c7f5d13cf599edef0f443c815a870abb68ca9
  - path: Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift
    blob: d722902132403acac8d2baba565c8ae1dc702802
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift
    blob: 4cb323df38334aa13ad4ecf68c10c0d76c1b9c0c
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialog.swift
    blob: 28f6efa09540598d7311a777da5d4be4f0a4452e
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift
    blob: 5e69c48782936c4c950b83ceac7b9128b6fee63a
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDiscardToast.swift
    blob: 2ed1f32bbe49a090527a60702ca5327d5388df1a
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift
    blob: 06a658dd99a504d7070da3d86adc5df1cb4fb9e7
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Screens/SettingsScreen.swift
    blob: e978d8960e17217951e68ad6c3526c339406e4a9
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift
    blob: 5452d6d89718a357dc8dcb15121f9e6b3c9927cc
  - path: Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift
    blob: 1bf4ae6409a26c607411ef5490b451172f3d99c4
  - path: Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift
    blob: 7554432d2a5789cff05e0782273f9e4bd3a22bc7
  - path: Packages/LillistUI/Sources/LillistUI/iOS/TaskEditorOverlay.swift
    blob: 338e254d1fe3a62733a107b80dfbcde8b38d491d
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ToastChrome.swift
    blob: 4c1b8698952989ed789fa615e748eef1ec4a2723
references_modules: [Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Components-chunk-2, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-Tasks]
generator: cartographer/4
baseline: 5882526e2241d4d941bb92533d13ae24f2d9cf17
---

# Module: Packages/LillistUI/Sources/LillistUI/iOS (misc)

## Purpose

Bundles the iOS-specific presentation primitives that sit between LillistCore and the iOS app shells: the primary task-list screen (TasksScreen), Quick Capture dialog and its overlay modifier, the floating add button, a toast system for archive/discard/failure feedback, the sync status badge, the settings screen shell, and routing helpers (SizeClassRouter, QuickCaptureActionEnvironment). The unifying invariant is the container/presenter split: every piece is a pure presenter whose data arrives via init and whose actions arrive via closures, so none of them reaches into stores or the app environment directly. Without this module the iOS UI has no primary task surface, no Quick Capture affordance, no toast feedback channel, and no size-class routing.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ArchiveToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ArchiveToast.swift:12` | Tappable undo pill; auto-dismisses in 4 s; caller binds `isPresented`, provides `onUndo`; attach as `.overlay(alignment: .bottom)` |
| `DiagnosticZipDocument` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift:56` | FileDocument wrapping a diagnostic .zip for `.fileExporter`; initialises from a URL or ReadConfiguration; `fileWrapper` returns in-memory data |
| `DiagnosticsIncludeSheet` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift:8` | Pure-presenter sheet for diagnostic-package include options; two Bool bindings + Create/Cancel closures via init; no env coupling |
| `EnvironmentValues` | extension | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift:14` | Exposes `\.quickCaptureAction` on EnvironmentValues; lets view-tree CTAs trigger Quick Capture without threading a binding up to the shell |
| `FloatingAddButton` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:8` | 52pt glass-circle FAB; `onTap` fires on press; optional `onLongPress` fires on hold and on a named accessibility action; no internal mutable state |
| `Layout` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift:8` | Equatable+Sendable enum with two cases (.tab, .split) representing iOS layout modes; output of SizeClassRouter.layout(for:) |
| `QuickCaptureActionKey` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift:10` | EnvironmentKey delivering a `@MainActor () -> Void` Quick Capture trigger; default is a no-op so views compile without an injected shell value |
| `QuickCaptureDialog` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialog.swift:20` | iOS Quick Capture text field + parsed tag/date chips + Add button; no async work or store coupling; caller binds `text` and handles `onSubmit` |
| `QuickCaptureDiscardToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDiscardToast.swift:12` | Auto-dismissing "Discarded · Undo" pill; `onUndo` fires on Undo tap; auto-dismisses in 4 s; attach as `.overlay(alignment: .bottom)` |
| `ReorderFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:46` | Canned "Couldn't move that item" failure pill; wraps TransientFailureToast; attach as `.overlay(alignment: .bottom)` |
| `SettingsScreen` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Screens/SettingsScreen.swift:17` | iOS Settings NavigationStack shell with Form, inline title, Done button; sections supplied via @ViewBuilder so app-target keeps env-coupled section code |
| `SizeClassRouter` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift:7` | Namespace providing `layout(for:)` to convert UserInterfaceSizeClass to Layout; nil size class is treated as compact |
| `StatusChangeFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:68` | Canned "Couldn't update that task" failure pill; wraps TransientFailureToast; distinguishes silent failure from a dead status tap |
| `SyncStatusBadge` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:14` | Sync-state dot/icon badge with 44pt hit area; tapping while paused fires `onPausedTap`; emits VoiceOver announcements on indicator changes |
| `TasksScreen` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:15` | Primary iOS task-list surface; pure presenter; accepts a live DragController and @MainActor closures for all user actions; host owns fetch and state |
| `TransientFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:8` | General-purpose auto-dismissing failure pill; caller supplies `message` string; auto-dismisses in 4 s; attach as `.overlay(alignment: .bottom)` |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift:4` | Adds `.quickCaptureDialog(isPresented:onCancel:content:)` to all Views; upper-third anchored, dim-backed; Esc and tap-outside both cancel |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/iOS/TaskEditorOverlay.swift:4` | Adds `.taskEditorOverlay(isPresented:onCancel:content:)` to all Views; keyboard-aware float that lifts the editor card above the keyboard |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/iOS/ToastChrome.swift:4` | Adds `rainbowToastChrome()` to View; unifies glass-capsule + hairline border + lift elevation across all four toast types |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift:42` | Overlays dim backdrop + dialog; fires `onCancel` before flipping `isPresented` on tap-outside or Esc; accessibility-motion-gated scale transition |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/iOS/TaskEditorOverlay.swift:28` | Dim-backed keyboard-aware overlay; Esc and tap-outside fire `onCancel` before flipping `isPresented`; accessibility-motion-gated scale transition |
| `fileWrapper` | func | `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift:69` | Returns FileWrapper(regularFileWithContents: data); required by FileDocument for `.fileExporter` write path |
| `layout` | func | `Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift:10` | Returns .split for .regular, .tab for compact or nil; pure function with no side effects; safe to call from any isolation context |
| `makeBody` | func | `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:57` | Applies 0.94 scale on press with squish animation; gated on `reduceMotionOverride ?? accessibilityReduceMotion`; no animation when reduced |
| `quickCaptureDialog` | func | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift:17` | Modifier for centered iOS dialog overlay; `onCancel` fires before `isPresented = false` so hosts can capture text for an Undo affordance |
| `rainbowToastChrome` | func | `Packages/LillistUI/Sources/LillistUI/iOS/ToastChrome.swift:15` | Wraps content in glassSurface(.toast)/Capsule with hairline border and `.lift` elevation; host must wrap co-visible toasts in `glassGroup()` |
| `taskEditorOverlay` | func | `Packages/LillistUI/Sources/LillistUI/iOS/TaskEditorOverlay.swift:10` | Modifier for floating editor card; keyboard-aware (unlike quickCaptureDialog); tap-outside and Esc fire `onCancel` before dismissal |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `TaskEditorOverlay` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/TaskEditorOverlay.swift:19` | Implements all keyboard-aware overlay behavior — backdrop dim, scale/opacity transition gated on reduceMotion, Esc key handler, accessibleAnimation — that the public `taskEditorOverlay()` modifier exposes; the public extension is only syntactic sugar (TaskEditorOverlay.swift:19-64). |
| `reasonDescription` | func | `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:113` | Centralizes PauseReason-to-string translation used by both the static accessibility label (SyncStatusBadge.swift:102) and the dynamic `.onChange` announcement (SyncStatusBadge.swift:81); a split implementation would allow the two text forms to diverge silently. |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.move (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleAnimation (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.TagChipView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassSurface (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialogPresenter -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.move (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleAnimation (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ReorderFailureToast -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SettingsScreen -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SettingsScreen -> Packages-LillistUI-Sources-LillistUI-Settings.settingsFormStyle (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SquishPressStyle -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.StatusChangeFailureToast -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.fill (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TaskEditorOverlay -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.move (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.BuildVersionLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.RainbowEmptyStateView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.reportRowGeometry (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.move (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleAnimation (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.View -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.View -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.glassGroup (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.body -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.body -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleAnimation (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.makeBody -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.squish (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Apps-Lillist-macOS-Sources-Hotkey.toggle (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.SwipeActionSpec (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Packages-LillistUI-Sources-LillistUI-DragReorder.dragReorderGesture (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.accessibilityLabel (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.outlineRow -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.phantomRow -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.rainbowCard (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.phantomRow -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2.TaskRowView (calls)`

## Type notes

All Views are pure presenters; data and action closures arrive via `init`. The only mutable state inside this module is `TasksScreen`'s `@ObservedObject var dragController: DragController` (live mutation sink for drag events, not a binding) and `@State private var openSwipeRowID: UUID?` for swipe-row exclusivity (TasksScreen.swift:35,39). Quick Capture and task-editor overlays hold only `@FocusState` (QuickCaptureDialog.swift:24).

Files marked `// Cross-platform: shared by the iOS app and the macOS main window.` compile on both platforms: ArchiveToast, FloatingAddButton, ReorderFailureToast, SyncStatusBadge, TasksScreen, TaskEditorOverlay, ToastChrome. Files with `#if os(iOS)` guards compile on iOS only: QuickCaptureDialog.swift:1, SettingsScreen.swift:1, SizeClassRouter.swift:1, QuickCaptureDialogPresenter.swift:1, QuickCaptureDiscardToast.swift:1.

`QuickCaptureActionKey.defaultValue` is typed `@MainActor () -> Void` so callers deep in the view tree can invoke it without an isolation cast (QuickCaptureActionEnvironment.swift:11). All action closures on TasksScreen are `@MainActor`-annotated (TasksScreen.swift:43-51).

Toast auto-dismiss uses `.task(id: isPresented)` rather than a Timer; SwiftUI cancels the task automatically when the view disappears or `isPresented` flips (ArchiveToast.swift:45-51; QuickCaptureDiscardToast.swift:46-52; TransientFailureToast in ReorderFailureToast.swift:28-35).

## External deps

- LillistCore — imported
- SwiftUI — imported
- UniformTypeIdentifiers — imported

## Gotchas

- TasksScreen.swift:219-224: `coordinateSpace(name:)` must be on the `List` itself, not a wrapping ZStack — SwiftUI's named coordinate spaces do not propagate through List's internal UICollectionView, so `proxy.frame(in: .named(...))` returns wrong positions if the space is placed on a parent.
- TasksScreen.swift:156-163: Co-visible toasts are stacked in a VStack rather than a `GlassEffectContainer` to prevent the container from blanking every offscreen snapshot of the screen; an always-present container would affect the common no-toast state.
- TasksScreen.swift:329-352 (`outlineRow`): The drag-reorder gesture and tap are attached only to the text label closure, not the full row — a full-row `Button` wins gesture arbitration over the long-press drag recognizer and starves it (see engineering-notes 2026-06-17).
- ToastChrome.swift:12-13: `rainbowToastChrome()` does NOT call `glassGroup()` — the comment explicitly states the host must wrap co-visible toasts in `glassGroup()` to prevent glass capsules from sampling each other.
