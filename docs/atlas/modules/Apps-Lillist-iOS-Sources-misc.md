---
module: "Apps/Lillist-iOS/Sources (misc)"
summary: "iOS container layer: TasksView lifecycle + store wiring, TaskEditorHost overlay, onboarding, and keyboard commands."
read_when: "iOS root shell or Quick Capture"
sources:
  - path: Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift
    blob: 166463128417565918949336bd955c5f5226882c
  - path: Apps/Lillist-iOS/Sources/Common/SceneBindings.swift
    blob: 4c5ed74be926c762f0403a874c3427d9b503d503
  - path: Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift
    blob: b5cb34a4116cae92809b56067cd2b387997f924b
  - path: Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift
    blob: bd8a5898a5de3b3ec6ebf2feb8ce63b9659f4758
  - path: Apps/Lillist-iOS/Sources/Root/RootShell.swift
    blob: 8adba00f5dcabd13817ce262915f3f9963ce92ab
  - path: Apps/Lillist-iOS/Sources/Tasks/TasksView.swift
    blob: 5a13daa91261f6f9a4310968d8a49413992baecd
references_modules: [Apps-Lillist-iOS-Sources-Settings-misc, Apps-Lillist-macOS-Sources-Hotkey, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-DragReorder, Packages-LillistUI-Sources-LillistUI-Editor, Packages-LillistUI-Sources-LillistUI-Onboarding, Packages-LillistUI-Sources-LillistUI-Recurrence, Packages-LillistUI-Sources-LillistUI-Settings, Packages-LillistUI-Sources-LillistUI-Status, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-iOS-misc]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Apps/Lillist-iOS/Sources (misc)

## Purpose

This module is the iOS app's state-owning container layer: it bridges the stateless LillistUI presenters to AppEnvironment stores, and keeps all @State, .task lifecycle, navigation wiring, and action dispatch inside the app target. TasksView is the single primary surface — it owns fetch, filter, sort, drag-drop, and all mutation callbacks. TaskEditorHost attaches the unified editor as a singleton floating ViewModifier. Without this layer, the LillistUI screens would have no store connectivity, no lifecycle, and no navigation.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `EnvironmentValues` | extension | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:22` | Exposes isQuickCapturePresentedBinding and sortBinding as environment values; callers read/write bindings to drive Quick Capture and sort state across the scene. |
| `IsQuickCapturePresentedBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:14` | EnvironmentKey for the Quick Capture binding; default is .constant(false). The scene root must inject the real Binding<Bool> for the FAB and ⌘⇧N to work. |
| `LillistCommands` | struct | `Apps/Lillist-iOS/Sources/Commands/LillistCommands.swift:15` | Provides the iOS scene-level Commands block; callers get a ⌘⇧N keyboard shortcut that sets $isQuickCapturePresented = true. |
| `OnboardingScreen` | struct | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:16` | Full-screen onboarding cover; callers inject onboardingState, installer, notificationPermissions, and an onCompleted closure called once defaults are installed and state is marked done. |
| `RootShell` | struct | `Apps/Lillist-iOS/Sources/Root/RootShell.swift:12` | Top-level iOS view; callers get a NavigationStack wrapping TasksView — no configuration surface exposed. |
| `SortBindingKey` | struct | `Apps/Lillist-iOS/Sources/Common/SceneBindings.swift:18` | EnvironmentKey for the sort binding; default is .constant(.personalized). The scene root must inject the real @AppStorage-backed Binding<TasksSort>. |
| `TaskEditorHost` | struct | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:17` | ViewModifier that attaches a singleton floating task editor; callers apply .modifier(TaskEditorHost(...)) and pass newCaptureTrigger, openTaskID, captureSeed bindings plus stores and an onChanged callback. |
| `TasksView` | struct | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:9` | Single primary iOS surface; callers get the full task list with fetch lifecycle, filter/sort/drag-drop state, FAB, and unified editor overlay — driven entirely by AppEnvironment from the environment. |
| `body` | func | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:35` | Returns content layered with the editor overlay, photos picker, and discard toast; callers rely on it observing all three trigger bindings and calling onChanged after any mutation. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `applyDrop` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:327` | Routes drag-drop through DragDropResolver to reorder, reparent, or noop — the sole drag persistence path on iOS. @MainActor-isolated to keep store calls on the main actor. |
| `buildActivePredicateGroup` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:226` | Every reload path flows through this function; it composes the active PredicateGroup from quick tokens, saved filters, and search text — the single source of what the list shows. |
| `cancel` | func | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:117` | Guards three distinct close paths: pure-draft discard with undo toast, promoted-draft close (already in Trash), and existing-task save-text-and-close. The branch on model.taskID == nil (line 125) is the key invariant; a mistake here would either suppress valid undo or offer undo for Trash items. |
| `complete` | func | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:122` | Sequences installIfNeeded → markCompleted → onCompleted; any error surfaces in the UI and emits an accessibility announcement. It is the single gate that transitions the app from onboarding to normal operation. |
| `cycle` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:348` | Thin but canonical entry point for status cycling; delegates to StatusCycler.nextOnClick then setStatus, keeping the click-to-cycle path single-threaded through one function. |
| `dismissCommitted` | func | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:109` | Enforces the committed-vs-cancel semantic split: sets isPresented = false and fires onChanged after an explicit Done/Add action. Without it, committed tasks would not trigger a list refresh. |
| `initialLoad` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:171` | Sequences filter load, sibling-order normalization, and list reload on launch — ordering matters: normalization must run before the first reload to avoid stale sibling positions. |
| `loadSavedFilters` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:177` | Loads and normalizes saved filters before every use; silently falls back to empty on failure so a corrupt filter store does not block the whole task list. |
| `openExisting` | func | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:100` | Sole path for editing an existing task on iOS; creates and loads a TaskEditorModel for the given UUID and re-targets the singleton (replacing any open editor). |
| `openNewCapture` | func | `Apps/Lillist-iOS/Sources/Editor/TaskEditorHost.swift:92` | Sole path for opening a new capture draft; enforces singleton constraint with !isPresented guard and applies any prefill text before presenting. |
| `performRefreshArchive` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:293` | Pull-to-refresh handler that archives visible closed tasks and presents the undo toast; guarded to fall back to a plain reload when the Done filter is active so the user's history view is not emptied. |
| `reload` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:195` | Central list refresh path; wraps records reassignment in withAnimation and guards first-load with hasLoadedOnce to suppress the launch cascade animation (TasksView.swift:204-207). |
| `requestPermission` | func | `Apps/Lillist-iOS/Sources/Onboarding/OnboardingScreen.swift:116` | Sole notification permission request path in iOS onboarding; updates permissionStatus so the button self-disables once the system has answered. |
| `setStatus` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:357` | Writes status transitions via taskStore.transition and surfaces the status toast on failure — per the dead-status-tap RCA comment at line 355, silent failure must be distinguishable from a tap that never fired. |
| `undoArchive` | func | `Apps/Lillist-iOS/Sources/Tasks/TasksView.swift:311` | Restores exactly the last archived batch (lastArchivedBatch) via taskStore.unarchive; scoped to prevent a second pull-to-refresh from accidentally resurrecting an older batch. |

## Relationships

- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Apps-Lillist-macOS-Sources-Hotkey.open (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistCore-Sources-LillistCore-Notifications.currentStatus (reads)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Accessibility.accessibleMaterial (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.DotGridBackdrop (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.Color (calls)`
- `Apps-Lillist-iOS-Sources-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Apps-Lillist-iOS-Sources-Settings-misc.SettingsTab (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.softDelete (writes)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-DragReorder.DragController (owns)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-Editor.Stores (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks.SavedFilterChipSpec (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.FloatingAddButton (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen (calls)`
- `Apps-Lillist-iOS-Sources-misc.body -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView (calls)`
- `Apps-Lillist-iOS-Sources-misc.body -> Packages-LillistUI-Sources-LillistUI-Editor.addImageAttachment (writes)`
- `Apps-Lillist-iOS-Sources-misc.body -> Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDiscardToast (calls)`
- `Apps-Lillist-iOS-Sources-misc.body -> Packages-LillistUI-Sources-LillistUI-iOS-misc.taskEditorOverlay (calls)`
- `Apps-Lillist-iOS-Sources-misc.buildActivePredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.Leaf (calls)`
- `Apps-Lillist-iOS-Sources-misc.buildActivePredicateGroup -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (calls)`
- `Apps-Lillist-iOS-Sources-misc.buildActivePredicateGroup -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Apps-Lillist-iOS-Sources-misc.cancel -> Packages-LillistUI-Sources-LillistUI-Editor.discard (writes)`
- `Apps-Lillist-iOS-Sources-misc.cancel -> Packages-LillistUI-Sources-LillistUI-Editor.saveTextNow (writes)`
- `Apps-Lillist-iOS-Sources-misc.complete -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Apps-Lillist-iOS-Sources-misc.complete -> Packages-LillistCore-Sources-LillistCore-misc.installIfNeeded (writes)`
- `Apps-Lillist-iOS-Sources-misc.complete -> Packages-LillistCore-Sources-LillistCore-misc.markCompleted (writes)`
- `Apps-Lillist-iOS-Sources-misc.complete -> Packages-LillistUI-Sources-LillistUI-Accessibility.post (emits)`
- `Apps-Lillist-iOS-Sources-misc.cycle -> Packages-LillistUI-Sources-LillistUI-Status.nextOnClick (reads)`
- `Apps-Lillist-iOS-Sources-misc.initialLoad -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.normalizeSiblingsIfDegenerate (writes)`
- `Apps-Lillist-iOS-Sources-misc.loadSavedFilters -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeIfDegenerate (writes)`
- `Apps-Lillist-iOS-Sources-misc.openExisting -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel (owns)`
- `Apps-Lillist-iOS-Sources-misc.openNewCapture -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel (owns)`
- `Apps-Lillist-iOS-Sources-misc.performRefreshArchive -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.archive (writes)`
- `Apps-Lillist-iOS-Sources-misc.reload -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.easeOut (reads)`
- `Apps-Lillist-iOS-Sources-misc.setStatus -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.transition (writes)`
- `Apps-Lillist-iOS-Sources-misc.undoArchive -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.unarchive (writes)`

## Type notes

TaskEditorHost is a ViewModifier (TaskEditorHost.swift:17), not a View; applied via .modifier() in TasksView.swift:108. Its @State var model: TaskEditorModel? (TaskEditorHost.swift:28) enforces the singleton: openNewCapture guards !isPresented (line 93), openExisting re-targets unconditionally (line 102). TasksView reads AppEnvironment via @Environment(AppEnvironment.self) (TasksView.swift:10) and drives all store mutations through it; @State var records is the sole copy of the fetched list. SceneBindings uses Binding<T> as the EnvironmentKey default (SceneBindings.swift:15,19) so LillistApp can inject real @State/@AppStorage bindings without @EnvironmentObject. applyDrop is explicitly @MainActor (TasksView.swift:326) because DragDropResolver and store calls must run on the main actor. hasLoadedOnce (TasksView.swift:33) suppresses the initial list animation; every subsequent reload animates with LillistMotion.easeOut (TasksView.swift:204-207).

## External deps

- LillistCore — imported
- LillistUI — imported
- PhotosUI — imported
- SwiftUI — imported

## Gotchas

Cold-launch seed race in TaskEditorHost: captureSeed may be set before body appears, so .onChange(of: captureSeed) never fires. consumeSeed is also called from .task to handle this (TaskEditorHost.swift:81). — cancel() has three distinct branches: pure-draft (taskID == nil, offer undo toast), promoted-draft (taskID != nil, Trash-recoverable, no toast), existing task (non-capture, just saveTextNow+close) — the guard is model.taskID == nil at TaskEditorHost.swift:125; errors here either suppress valid undo or show toast for Trash items.
