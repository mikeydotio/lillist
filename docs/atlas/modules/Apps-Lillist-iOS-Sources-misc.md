---
module: "Apps/Lillist-iOS/Sources (misc)"
summary: "iOS root shell, task list container, unified editor host, onboarding, and scene command/binding plumbing"
read_when: "iOS root shell, Quick Capture, task editor overlay, onboarding, or scene bindings"
sources:
  - path: Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift
    blob: 166463128417565918949336bd955c5f5226882c
  - path: Apps/Lillist-iOS/Sources/Common/SceneBindings.swift
    blob: 4c5ed74be926c762f0403a874c3427d9b503d503
  - path: Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift
    blob: e3878642168a8fe675bb69e4de980d00390003e8
  - path: Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift
    blob: bd8a5898a5de3b3ec6ebf2feb8ce63b9659f4758
  - path: Apps/Lillist-iOS/Sources/Root/RootShell.swift
    blob: 8adba00f5dcabd13817ce262915f3f9963ce92ab
  - path: Apps/Lillist-iOS/Sources/Tasks/TasksView.swift
    blob: 96de4d0b6dd826ebfab4465fc73b25beff8a056e
references_modules: [Apps-Lillist-iOS-Sources-App, Apps-Lillist-iOS-Sources-Settings, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-misc]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Apps/Lillist-iOS/Sources (misc)

## Purpose

The iOS app-target glue between SwiftUI scenes and the shared `LillistUI` presentation layer,
after the 3-tab restructure collapsed to a single primary surface. Container views own `@State`,
`.task` lifecycle, `AppEnvironment` reads, and navigation wiring while delegating all rendering to
pure `LillistUI` screens. `TaskEditorHost` replaced `QuickCaptureDialogHost`: a singleton floating
overlay that handles both new capture and full task editing. If this layer vanished, the iOS app
would have no root shell, no list-to-store mutation routing, and no editor or onboarding entry points.

## Public API

These types are `internal` to the `Lillist-iOS` target; "public surface" here means the
symbols other files in the target construct or wire up.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `IsQuickCapturePresentedBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:14` | EnvironmentKey defaulting the Quick Capture presentation binding to `.constant(false)` |
| `LillistCommands` | struct | `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift:15` | Scene `Commands`; exposes only Quick Capture (`⌘⇧N`) to the iPadOS hold-⌘ overlay |
| `OnboardingScreen` | struct | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:16` | First-launch full-screen cover; takes four injected deps, calls `onCompleted` when done |
| `RootShell` | struct | `Apps/Lillist-iOS/Sources/Root/RootShell.swift:12` | Top-level iOS shell; `NavigationStack` with `TasksView` as sole primary content |
| `SortBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:18` | EnvironmentKey defaulting `TasksSort` selection to `.personalized` |
| `TaskEditorHost` | struct | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:17` | `ViewModifier` singleton floating editor; driven by `newCaptureTrigger` and `openTaskID` bindings |
| `TasksView` | struct | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:9` | Container for the single primary surface; owns fetch/reload and delegates to `TasksScreen` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `reload` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:192` | Single re-fetch path; every mutation and filter/sort/search change funnels through it |
| `buildActivePredicateGroup` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:223` | Composes quick tokens, saved filters, and search text into the store query |
| `applyDrop` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:324` | Routes resolved drag-drop to reorder/reparent store mutations via `DragDropResolver` |
| `setStatus` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:352` | Status transition; surfaces a toast on failure rather than swallowing it |
| `performRefreshArchive` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:290` | Pull-to-refresh archives visible closed tasks and arms the undo banner |
| `isQuickCapturePresentedBinding` | var | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:23` | EnvironmentValues accessor shared by `LillistCommands`, the FAB, and `TaskEditorHost` |
| `complete` | func | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:122` | Calls `installer.installIfNeeded`, marks onboarding done, posts AX announcement on error |

## Relationships

- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.TasksScreen (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (owns)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-misc.StatusCycler (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-Settings.SettingsTab (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-App.AppEnvironment (reads)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-misc.TaskEditorHost (owns)`
- `Apps-Lillist-iOS-Sources-misc.RootShell -> Apps-Lillist-iOS-Sources-misc.TasksView (calls)`
- `Apps-Lillist-iOS-Sources-misc.TaskEditorHost -> Packages-LillistUI-Sources-LillistUI-misc.TaskEditorView (calls)`
- `Apps-Lillist-iOS-Sources-misc.TaskEditorHost -> Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationPermissions (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.LillistCommands (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.RootShell (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.OnboardingScreen (calls)`

## Type notes

`TaskEditorHost` is a `ViewModifier`, not a `View` — applied via `.modifier(TaskEditorHost(...))` at
`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:109`. It is a singleton: opening while already
presented re-targets to the new task (existing) or is silently ignored (new capture). A discard of
a never-promoted draft triggers an undo toast (`QuickCaptureDiscardToast`) that re-opens the editor
with the preserved text (`Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:120–125`).

`TasksView` reads dependencies via `@Environment(AppEnvironment.self)` (e.g.
`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:10`), never holding stores directly. Scene state
lives one level up in `LillistApp`: the two EnvironmentKeys in `SceneBindings.swift` thread
`Binding<Bool>` (Quick Capture presentation) and `Binding<TasksSort>` (`@AppStorage`-backed sort)
down to deep views; both default to `.constant(...)` so previews render without a host.

`RootShell` retired the `NavigationSplitView` + detail column in favor of a plain `NavigationStack`;
row taps set `openTaskID` which `TaskEditorHost` observes to open the floating editor
(`Apps/Lillist-iOS/Sources/Root/RootShell.swift:14`).

`applyDrop` is `@MainActor` and uses `DragDropResolver` as the single drop-resolution source shared
with macOS. First populate is unanimated via `hasLoadedOnce`
(`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:33`). Search input is debounced with a 250 ms
`Task.sleep` cancellation pattern (`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:126–134`).

`OnboardingScreen` follows explicit constructor injection — the presenting view reads
`@Environment(AppEnvironment.self)` and forwards only the four needed dependencies
(`Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:17–20`).

## External deps

- SwiftUI — all views, `Commands`, `EnvironmentKey`, `NavigationStack`, `@AppStorage`
- PhotosUI — `PhotosPicker` for image attachment selection in `TaskEditorHost`
- LillistCore — store DTOs, predicate/rules value types, notification permission types
- LillistUI — presenter screens, theme tokens, drag controller, editor view, discard toast

## Gotchas

- `LillistCommands` uses `⌘⇧N` (not `⌘N`) because `⌘N` is reserved by iPadOS (`Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift:9`).
- `setStatus` raises a toast on a failed write rather than swallowing it, per the dead-status-tap RCA (`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:352`).
- Pull-to-refresh in the Done view falls back to plain reload so it doesn't archive the tasks the user is browsing (`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:291–294`).
