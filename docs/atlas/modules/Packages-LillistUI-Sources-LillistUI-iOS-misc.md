---
module: "Packages/LillistUI/Sources/LillistUI/iOS (misc)"
summary: "iOS-only LillistUI surfaces — FAB, Quick Capture dialog, toasts, sync badge, and the Tasks/Settings screen shells"
read_when: iOS Quick Capture, FAB, toasts
sources:
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ArchiveToast.swift
    blob: 29e16f29a8e2cef387387bcc878d5790d533c5a8
  - path: Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift
    blob: d47c7f5d13cf599edef0f443c815a870abb68ca9
  - path: Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift
    blob: 1506081b02d63f3f398bc950fb1a6dc7027c9b0a
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift
    blob: 4cd70e2ac439f86bdb12031e3784ddf7ebdea73b
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialog.swift
    blob: 28f6efa09540598d7311a777da5d4be4f0a4452e
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift
    blob: 5e69c48782936c4c950b83ceac7b9128b6fee63a
  - path: Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDiscardToast.swift
    blob: 2ed1f32bbe49a090527a60702ca5327d5388df1a
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift
    blob: 0715994fd02c6510687e9d41a630777fac072dcb
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Screens/SettingsScreen.swift
    blob: 35b24834fa6e44b5e3cf8a41693bdd914b0d678f
  - path: Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift
    blob: ec7bb4b5af67a83610c42c39b93cdcb8732cca1d
  - path: Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift
    blob: 1bf4ae6409a26c607411ef5490b451172f3d99c4
  - path: Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift
    blob: deb46ec7b905384f236781bd3cb27ca4f5697666
  - path: Packages/LillistUI/Sources/LillistUI/iOS/ToastChrome.swift
    blob: b70db2d1499bec0e34c308d83e8587d7f0062637
references_modules: [Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-QuickCapture, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-misc, Packages-LillistCore-Sources-LillistCore-Model]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/iOS (misc)

## Purpose

The iOS-only presentation primitives of LillistUI: the floating add button, the
Spotlight-style Quick Capture dialog and its presenter modifier, the family of
bottom-anchored transient toasts, the sync-status badge, and the two top-level
screen shells (Tasks, Settings). Every type here is *pure presentation* —
data and action closures arrive via `init`, with no `@State` beyond focus, no
`.task` lifecycle, and no `AppEnvironment` coupling — so `IOSScreenTourTests`
can render them with frozen mock data. The iOS app target supplies the state,
fetches, and navigation destinations that these views can't reach.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ArchiveToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ArchiveToast.swift:12` | Plural-aware "N archived. Tap to undo." pill; whole capsule fires `onUndo`; self-dismisses |
| `DiagnosticZipDocument` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift:56` | `FileDocument` wrapping a finished diagnostic `.zip` for `.fileExporter`; iOS + macOS |
| `DiagnosticsIncludeSheet` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift:8` | Stateless include-step sheet (two toggles + Create/Cancel via `init` bindings) |
| `FloatingAddButton` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:8` | 52pt glass FAB; `onTap` create, optional `onLongPress` clipboard affordance |
| `QuickCaptureActionKey` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift:10` | EnvironmentKey carrying a `@MainActor () -> Void` present-Quick-Capture closure |
| `QuickCaptureDialog` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialog.swift:20` | Centered capture field; renders parser chips; `onSubmit` on Return/Add |
| `QuickCaptureDiscardToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDiscardToast.swift:12` | "Discarded · Undo" pill; `onUndo` restores text and re-presents the dialog |
| `ReorderFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:46` | Fixed-copy drag-reorder failure pill over `TransientFailureToast` |
| `SettingsScreen` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Screens/SettingsScreen.swift:17` | Chrome-only Settings shell; caller passes `Form` sections via ViewBuilder |
| `SizeClassRouter` | enum | `Packages/LillistUI/Sources/LillistUI/iOS/SizeClassRouter.swift:7` | Maps size class to `.tab`/`.split`; `nil` defaults to compact `.tab` |
| `StatusChangeFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:68` | Fixed-copy status-write failure pill (dead-status-tap RCA hardening) |
| `SyncStatusBadge` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:14` | 44pt sync indicator button; taps `onPausedTap` only when `.paused` |
| `TasksScreen` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:14` | The iOS app's primary surface: outline list, filter header, toolbar, toasts |
| `TransientFailureToast` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/ReorderFailureToast.swift:8` | Generic no-undo failure pill base; self-dismisses; parameterized `message` |
| `quickCaptureAction` | property | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureActionEnvironment.swift:15` | `EnvironmentValues` accessor for the present-Quick-Capture closure |
| `quickCaptureDialog(isPresented:onCancel:content:)` | func | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift:17` | `View` modifier: dim backdrop, tap/Esc dismiss, `onCancel` before flip |
| `rainbowToastChrome()` | func | `Packages/LillistUI/Sources/LillistUI/iOS/ToastChrome.swift:15` | Shared glass-capsule toast chrome so the four toasts can't drift apart |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `QuickCaptureDialogPresenter` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/QuickCaptureDialogPresenter.swift:30` | ViewModifier behind `quickCaptureDialog`; owns backdrop, transition, Esc handling |
| `syncDragControllerInputs(flat:)` | func | `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:280` | Pushes flat rows, sort mode, and filter-active flag into the `DragController` |
| `SquishPressStyle` | struct | `Packages/LillistUI/Sources/LillistUI/iOS/FloatingAddButton.swift:52` | FAB-local press squish gated on Reduce Motion; distinct from `RainbowButtonStyle` |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TreeFlattener (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterHeader (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TaskOutlineRowView (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen -> Packages-LillistUI-Sources-LillistUI-Components.RainbowEmptyStateView (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-Components.TagChipView (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistUI-Sources-LillistUI-misc.SyncIndicator (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.SyncStatusBadge -> Packages-LillistCore-Sources-LillistCore-Model.Status (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ArchiveToast -> Packages-LillistUI-Sources-LillistUI-iOS-misc.rainbowToastChrome (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast -> Packages-LillistUI-Sources-LillistUI-iOS-misc.rainbowToastChrome (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.ReorderFailureToast -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.StatusChangeFailureToast -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TransientFailureToast (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.quickCaptureDialog -> Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialogPresenter (calls)`

## Type notes

`SyncIndicator` (in LillistUI `Status/`) is `SyncStatusBadge`'s sole driver; its
`.paused(reason:)` case carries a `PauseReason` whose human copy is mapped by
`reasonDescription(_:)` at `Packages/LillistUI/Sources/LillistUI/iOS/SyncStatusBadge.swift:113`,
and a state change posts a VoiceOver announcement at line 62.
`SyncStatusBadge`, `TasksScreen` import `LillistCore`; `TasksScreen`'s action
closures traffic in `LillistCore` DTOs (`TaskStore.TaskRecord`, `Status`) but
never hold Core Data types.
All four toasts and the dialog presenter self-dismiss after ~4s via a
`.task(id:)` sleep and gate their entry transition on a reduce-motion override
(`overrideReduceMotion ?? systemReduceMotion`); the dialog is keyboard-driven
(`@FocusState`, focus on appear) and is the only stateful surface here.
`quickCaptureAction` is an *inbound* contract: the iOS shells inject the closure
into the environment and empty-state CTAs (e.g. `TasksScreen` emptyState at
`Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:189`) read it.

## External deps

- SwiftUI — every type is a `View`, `ViewModifier`, `ButtonStyle`, or `EnvironmentKey`
- UniformTypeIdentifiers — `DiagnosticZipDocument.readableContentTypes` returns `[.zip]`
- Foundation — `RelativeDateTimeFormatter` for the sync-badge "Last synced" label

## Gotchas

- Co-visible Liquid Glass toasts must not share a `GlassEffectContainer`: an always-present container blanks every offscreen snapshot of `TasksScreen`, so toasts stack in a plain `VStack` — `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:147`.
- `.coordinateSpace(name:)` must sit on the `List` itself, not a wrapping container, or drag-row frames resolve wrong through the internal collection view — `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:202`.
- The drag gesture wraps only the row's text label so chevron and status taps survive — `Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:294`.
