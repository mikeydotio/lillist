---
module: "Apps/Lillist-iOS/Sources (misc)"
summary: "iOS app shell, primary tasks container, onboarding, Quick Capture host, and scene command/binding plumbing"
read_when: "iOS root shell, Quick Capture"
sources:
  - path: Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift
    blob: 166463128417565918949336bd955c5f5226882c
  - path: Apps/Lillist-iOS/Sources/Common/SceneBindings.swift
    blob: 4c5ed74be926c762f0403a874c3427d9b503d503
  - path: Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift
    blob: bd8a5898a5de3b3ec6ebf2feb8ce63b9659f4758
  - path: Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureDialogHost.swift
    blob: f1fd69a974c93c1313e4907e811648ee2e08038f
  - path: Apps/Lillist-iOS/Sources/Root/RootShell.swift
    blob: 81fd318944a7aa6870c2de2944e184f110e85dd7
  - path: Apps/Lillist-iOS/Sources/Tasks/TasksView.swift
    blob: b0f506a6514fcd5e46055989ca3695048ac1978f
references_modules: [Apps-Lillist-iOS-Sources-App, Apps-Lillist-iOS-Sources-Detail, Apps-Lillist-iOS-Sources-Settings, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-QuickCapture, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-iOS/Sources (misc)

## Purpose

The iOS app-target glue between SwiftUI scenes and the shared `LillistUI` presentation
layer, after the 3-tab restructure collapsed to a single primary surface. These container
views own `@State`, `.task` lifecycle, `AppEnvironment` reads, and navigation wiring while
delegating all rendering to pure `LillistUI` screens — the container/presenter split that
lets tour tests render screens with frozen mock data. If this layer vanished, the iOS app
would have no root shell, no list-to-store mutation routing, and no Quick Capture or
onboarding entry points.

## Public API

These types are `internal` to the `Lillist-iOS` target; "public surface" here means the
symbols other files in the target construct or wire up.

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `IsQuickCapturePresentedBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:14` | EnvironmentKey defaulting the Quick Capture presentation binding to `.constant(false)` |
| `LillistCommands` | struct | `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift:15` | Scene `Commands`; exposes only Quick Capture (`⌘⇧N`) to the iPadOS hold-⌘ overlay |
| `OnboardingScreen` | struct | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:16` | First-launch full-screen cover; takes four injected deps, calls `onCompleted` when done |
| `QuickCaptureDialogHost` | struct | `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureDialogHost.swift:19` | ViewModifier hosting the capture dialog + discard toast; runs parse→create→tag→deadline |
| `RootShell` | struct | `Apps/Lillist-iOS/Sources/Root/RootShell.swift:15` | Top-level iOS shell; `NavigationSplitView` with `TasksView` sidebar + detail column |
| `SortBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:18` | EnvironmentKey defaulting `TasksSort` selection to `.personalized` |
| `TasksView` | struct | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:9` | Container for the single primary surface; owns fetch/reload and delegates to `TasksScreen` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `reload` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:170` | Single re-fetch path; every mutation and filter/sort/search change funnels through it |
| `buildActivePredicateGroup` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:201` | Composes quick tokens, saved filters, and search text into the store query |
| `submit` | func | `Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureDialogHost.swift:68` | Quick Capture pipeline; holds the empty-title gate and double-write lock |
| `applyDrop` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:302` | Routes resolved drag-drop to reorder/reparent store mutations |
| `setStatus` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:330` | Status transition; surfaces a toast on failure rather than swallowing it |
| `performRefreshArchive` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:268` | Pull-to-refresh archives visible closed tasks and arms the undo banner |
| `isQuickCapturePresentedBinding` | var | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:23` | EnvironmentValues accessor shared by `LillistCommands`, the FAB, and the host |

## Relationships

- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (owns)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragDropResolver (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-misc.StatusCycler (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-Settings.SettingsTab (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-App.AppEnvironment (reads)`
- `Apps-Lillist-iOS-Sources-misc.RootShell -> Apps-Lillist-iOS-Sources-Detail.TaskDetailView (calls)`
- `Apps-Lillist-iOS-Sources-misc.RootShell -> Apps-Lillist-iOS-Sources-misc.TasksView (calls)`
- `Apps-Lillist-iOS-Sources-misc.QuickCaptureDialogHost -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser (calls)`
- `Apps-Lillist-iOS-Sources-misc.QuickCaptureDialogHost -> Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialog (calls)`
- `Apps-Lillist-iOS-Sources-misc.QuickCaptureDialogHost -> Packages-LillistCore-Sources-LillistCore-Rules.RelativeDateResolver (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.LillistCommands (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.RootShell (calls)`
- `Apps-Lillist-iOS-Sources-App.LillistApp -> Apps-Lillist-iOS-Sources-misc.OnboardingScreen (calls)`

## Type notes

`TasksView`, `QuickCaptureDialogHost`, and `OnboardingScreen` read dependencies via
`@Environment(AppEnvironment.self)` (e.g. `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:10`),
never holding stores directly. Scene state lives one level up in `LillistApp`: the two
EnvironmentKeys in `SceneBindings.swift` thread `Binding<Bool>` (Quick Capture presentation)
and `Binding<TasksSort>` (`@AppStorage`-backed sort) down to deep views; both default to
`.constant(...)` so previews render without a host. `submit()` is guarded against
double-writes by the `submitting` flag and gates empty titles inline since the redesigned
dialog has no Save button (`Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureDialogHost.swift:75`).
`applyDrop` is `@MainActor` and uses `DragDropResolver` as the single drop-resolution source
shared with macOS. First populate is unanimated via `hasLoadedOnce`
(`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:33`).

## External deps

- SwiftUI — all views, `Commands`, `EnvironmentKey`, `NavigationSplitView`, `@AppStorage`
- LillistCore — store DTOs, predicate/rules value types, notification permission types
- LillistUI — presenter screens, theme tokens, Quick Capture parser/dialog, drag controller

## Gotchas

- Status-tap failures must stay distinguishable from no-op taps — `setStatus` raises a toast on a failed write (`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:330`), per the dead-status-tap RCA.
- `submit()` records a `quick_capture.submit_failed` breadcrumb on error as belt-and-suspenders against a future `try?` swallowing the failure (`Apps/Lillist-iOS/Sources/QuickCapture/QuickCaptureDialogHost.swift:108`).
- Pull-to-refresh in the Done view falls back to plain reload so it doesn't archive the tasks the user is browsing (`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:269`).
