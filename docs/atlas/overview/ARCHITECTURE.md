---
module: overview/ARCHITECTURE
summary: System architecture and cross-module relationships
sources:
  - path: docs/atlas/modules/Apps-Config.md
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings.md
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Commands.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-misc.md
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
  - path: docs/atlas/modules/Apps-misc.md
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
  - path: docs/atlas/modules/Extensions-ShortcutsActions-Entities.md
  - path: docs/atlas/modules/Extensions-ShortcutsActions-misc.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Diagnostics.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Model.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Notifications.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Ordering.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Support.md
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-misc.md
  - path: docs/atlas/modules/Packages-LillistCore-misc.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Accessibility.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-DragReorder.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Editor.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Onboarding.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-QuickCapture.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Recurrence.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Settings.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
  - path: docs/atlas/modules/Packages-LillistUI-misc.md
  - path: docs/atlas/modules/Tools.md
  - path: docs/atlas/modules/root-misc.md
scopes:
  - tree: Apps
  - tree: Extensions
  - tree: Packages
  - tree: Tools
generator: cartographer/1 model=claude-sonnet-4-6
---

# Architecture

## System shape

Lillist is a four-layer Apple-only stack: `LillistCore` (data) → `LillistUI` (SwiftUI presentations) → iOS and macOS app targets; with the Share Extension, Shortcuts/App Intents extension, and `lillist` CLI all reusing `LillistCore` directly. The boundary between LillistCore and every consumer above it is enforced by a single rule: no `NSManagedObject` escapes the package. All public store APIs return value-type DTOs (`TaskRecord`, `TagRecord`, etc.) that are constructed inside `context.perform` blocks, saved, and surfaced as Swift structs. LillistUI knows nothing of Core Data — it operates on DTOs and calls store methods via closures or direct injection.

The iOS and macOS apps are structurally parallel: each has an `@Observable AppEnvironment` that constructs every LillistCore store and scheduler once at launch, then injects it into the SwiftUI scene via `@Environment`. The macOS app has a three-column `NavigationSplitView`; the iOS app collapsed to a single `TasksView` container after a tab restructure. Both share all SwiftUI presentation components from LillistUI. The out-of-process consumers (Share Extension, App Intents, CLI) open the App-Group-shared Core Data store via `GatedPersistenceResolver`, which consults `MigrationGate` before allowing any open so a running sync-mode swap cannot be interrupted by a headless opener.

The sync seam is `NSPersistentCloudKitContainer`. A sync-mode change (local-only ↔ iCloud) is a store-level remove-and-re-add on one long-lived container orchestrated by `MigrationCoordinator` across eight phases. `MigrationJournal` persists each phase to a file so a crash mid-migration is recoverable. CloudKit event observability is exposed through `CloudKitEventBridge` → `SyncStatusMonitor` → `SyncStatus`, decoupling the UI from CloudKit's opaque notification stream.

## Module relationships

- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceHost (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (owns)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (owns)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistUI-Sources-LillistUI-iOS-misc.TasksScreen (calls)`
- `Apps-Lillist-iOS-Sources-misc.TasksView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-iOS-Sources-misc.TaskEditorHost -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView (calls)`
- `Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Apps-Lillist-iOS-Sources-Settings.runMigration -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator (calls)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (owns)`
- `Apps-Lillist-macOS-Sources-misc.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (owns)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Views.RootSplitView (calls)`
- `Apps-Lillist-macOS-Sources-misc.LillistApp -> Apps-Lillist-macOS-Sources-Hotkey.GlobalHotkeyMonitor (owns)`
- `Apps-Lillist-macOS-Sources-Views.TaskListView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Apps-Lillist-macOS-Sources-Views.SidebarView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey.QuickCapturePanelController -> Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorView (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane -> Packages-LillistUI-Sources-LillistUI-Sync.SyncMigrationChoiceSheet (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistCore-Sources-LillistCore-Persistence.GatedPersistenceResolver (calls)`
- `Extensions-ShareExtension-iOS.ShareRootView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Extensions-ShortcutsActions-misc.IntentSupport -> Packages-LillistCore-Sources-LillistCore-Persistence.GatedPersistenceResolver (calls)`
- `Extensions-ShortcutsActions-misc.AddTaskIntent -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.CLIBridge.AddHandler (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.LsHandler -> Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Ordering.FractionalPosition (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Recurrence.RecurrenceSpawner (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationReconciling (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (writes)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationCoordinator -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceReconfiguring (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.GatedPersistenceResolver -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.MigrationGate (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.SyncStatusMonitor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.CloudKitEventBridge (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler -> Packages-LillistCore-Sources-LillistCore-Rules.RelativeDateResolver (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules.SwiftEvaluator -> Packages-LillistCore-Sources-LillistCore-Rules.NSPredicateCompiler (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor.TaskEditorModel -> Packages-LillistUI-Sources-LillistUI-QuickCapture.QuickCaptureParser (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components.TaskRowView -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore.TaskRecord (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.GlassSurfaceModifier -> Packages-LillistUI-Sources-LillistUI-Accessibility.reduceTransparencyOverride (reads)`
- `Packages-LillistCore-Sources-lillist-cli-misc.main -> Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.AddCommand -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.StoreLocator (calls)`

## Data flow

**Quick-capture task create (iOS):** The user taps the FAB (`FloatingAddButton` in `Packages-LillistUI-Sources-LillistUI-iOS-misc`) which signals `TaskEditorHost` (in `Apps-Lillist-iOS-Sources-misc`) to present `TaskEditorView`. As the user types, `TaskEditorModel` (`Packages-LillistUI-Sources-LillistUI-Editor`) calls `QuickCaptureParser` to tokenize the text into title/tags/date. The new task stays as an in-memory draft until `ensureLive()` is triggered; at that point `TaskEditorModel` calls `TaskStore.create` (`Packages-LillistCore-Sources-LillistCore-Stores-chunk-2`) inside `context.perform`, saves, then calls `NotificationReconciling` to schedule any reminders and writes a `BreadcrumbBuffer` entry. The mutated `TaskRecord` DTO is returned to the view layer; no managed object leaves `LillistCore`.

**`lillist` CLI verb:** `main.swift` (`Packages-LillistCore-Sources-lillist-cli-misc`) runs `CLICanaryLifecycle` to arm crash detection, then dispatches into ArgumentParser. The matching `Command` struct (`Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1` or `-chunk-2`) calls `StoreLocator` (`Packages-LillistCore-Sources-LillistCore-CLIBridge-misc`) which checks `MigrationGate` before opening the App-Group store. The command delegates to a `CLIBridge` handler (`Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1` or `-chunk-2`) which resolves task tokens via `Resolver`, calls the appropriate store method, and returns DTOs. A `Renderer` (`Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers`) serializes the DTOs to JSON/TSV/pretty output.

**iCloud sync-mode swap:** The user toggles "iCloud Sync" in iOS Settings (`Apps-Lillist-iOS-Sources-Settings.ICloudSyncSection`) or macOS Preferences (`Apps-Lillist-macOS-Sources-Preferences.ICloudSyncPane`). Both call `MigrationCoordinator.beginEnable/beginDisable` (`Packages-LillistCore-Sources-LillistCore-Sync-chunk-1`). The coordinator writes a `MigrationJournal` entry, quiesces pending CloudKit events via `SyncQuiesceMonitor`, then calls `PersistenceReconfiguring` (`Packages-LillistCore-Sources-LillistCore-Persistence`) to remove and re-add the store with the new configuration. Each phase emits a `MigrationPhase` event consumed by `SyncMigrationProgressSheet` in the UI. Concurrent headless openers (CLI, extensions) that call `GatedPersistenceResolver` will abort with an error if the journal shows a migration in flight.

## Key invariants

- No `NSManagedObject` escapes `LillistCore`: all store public APIs return value-type `*Record` DTOs. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md` Purpose section; `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md` Purpose section.
- All cross-process store access goes through `GatedPersistenceResolver`, which consults `MigrationGate` before allowing an open. Evidence: `docs/atlas/modules/Extensions-ShareExtension-iOS.md` Relationships; `docs/atlas/modules/Extensions-ShortcutsActions-misc.md` Relationships; `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md` Relationships.
- `CLIBridge` handlers are the single verb layer shared by the `lillist` CLI and the Shortcuts App Intents extension — no business logic is reimplemented in either caller. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md` Purpose; `docs/atlas/modules/Extensions-ShortcutsActions-misc.md` Purpose.
- LillistUI screens are pure presentation (data and closures via `init`, no `@State`/`.task`/`AppEnvironment`). App-target wrappers own lifecycle. Evidence: `docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md` Purpose; `docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md` Purpose.
- Date math goes through `Calendar.date(byAdding:)`; `addingTimeInterval` is forbidden except the `afterCompletion` recurrence rule defined in absolute seconds. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md` Purpose.
- Smart filters run twin evaluators — `NSPredicateCompiler` (Core Data fetch) and `SwiftEvaluator` (in-memory) — kept in behavioral parity by a dedicated parity test suite. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md` Purpose.
- All targets share App Group `group.io.mikeydotio.Lillist`; the `Signing.xcconfig` indirection keeps the Apple Developer Team ID out of every committed file. Evidence: `docs/atlas/modules/Apps-Config.md` Purpose; `docs/atlas/modules/Extensions-ShortcutsActions-misc.md` External deps.
- A sync-mode change is a store-level remove+re-add on one long-lived container, never a container re-instantiation. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md` Purpose.
- Crash reporting is canary-based, opt-in, and user-mediated — no silent upload. Evidence: `docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md` Purpose.

<!-- atlas:index-facts -->
- Apple-only: Swift 6, SwiftUI, Core Data over NSPersistentCloudKitContainer, CloudKit sync
- Four layers: LillistCore (data) -> LillistUI (SwiftUI) -> iOS/macOS apps; extensions + CLI reuse core
- No NSManagedObject escapes LillistCore — public store APIs return value DTOs (TaskRecord etc.)
- Hand-written @NSManaged subclasses in ManagedObjects/; Core Data codegen is disabled
- TaskStore (Stores chunk 2) is the single async gateway for all LillistTask CRUD/reorder/status
- Date math goes through Calendar; RecurrenceExpander is canonical, never addingTimeInterval
- Smart filters run twin evaluators (NSPredicateCompiler + SwiftEvaluator) kept in parity
- CLIBridge handlers are the shared verb layer for the lillist CLI and Shortcuts intents
- All targets share App Group group.io.mikeydotio.Lillist; CLI/extensions open via GatedPersistenceResolver
- Sync mode swap = store remove+re-add on one container; MigrationGate guards headless opens
- LillistUI iOS screens are state-free presenters; app-target wrappers own @State/.task/nav
- Rainbow Glass theme tokens live in LillistUI/Theme; color is functional, not decorative
- Crash reporting is canary-based, opt-in, redacted, user-mediated (no silent upload)
- Two xcodegen project.yml specs generate the pbxprojs; CI gates on drift, runs post-push on main
<!-- /atlas:index-facts -->
