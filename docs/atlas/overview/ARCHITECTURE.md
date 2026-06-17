---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/Apps-Config.md
    blob: 6da913caa7a6e3eae0fe73e87eb91658dbb082c9
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
    blob: b34c5ee4d771d036fcc0b5670c3d48f0e8adb243
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings.md
    blob: 13ef280ecc5fe4797c3cf1612ed4e86c491ba895
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
    blob: 6737b6ecb3034f59ba598b74732c850c3178ffc1
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
    blob: 88a09057af3f5113f27b3ecdaaa23cbf1ad2931e
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Commands.md
    blob: 56c0b999fd9d182637ad341e1f6ad0fcb2caa4ca
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
    blob: 78d9987f4501e7444901e418fb5920fafb32a4b3
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
    blob: 4b4086d4e78cbc49c404d9aedfb8132820e4dd89
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views.md
    blob: f04f60a5f51608ac610016b98229dca5c6799b64
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-misc.md
    blob: bcd0a774fbef4f9df7bcacff61c26b6698df5554
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
    blob: 4e561a88981dd959f8b2d6d2b2b26d2820ceab8d
  - path: docs/atlas/modules/Apps-misc.md
    blob: ae54f377d1055f7adbc358fd3c93b0f1e189814d
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
    blob: b98e997c9b5259389eca31911d3992834559fde9
  - path: docs/atlas/modules/Extensions-ShortcutsActions-Entities.md
    blob: 3b22db719e8d62a33901e161f141003cdc1be311
  - path: docs/atlas/modules/Extensions-ShortcutsActions-misc.md
    blob: 7b2490d464894819f13da6d13eab289555299eb4
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md
    blob: 0ea7cfcf80199ab88141fcc3e61d9e694f50ad9a
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.md
    blob: b8a421fd959a761a5107148de00b02690b7901b7
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.md
    blob: 23806fe9c45e851aa6e0289bd0150ff0757568aa
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md
    blob: a13844d47c0fe3d6462d73b010be3b345f3b38e0
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md
    blob: 17dc1b9a061f52d8e486180a86709abc0d7d9986
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Diagnostics.md
    blob: b36c2c2d2105e275f4290cd0c03cee7840585423
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
    blob: 375b3ceec10012ce7771131dfb74b1312542be3d
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
    blob: ad75b53c382f5b1a1242b2044e7c5a02ddf3af65
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md
    blob: 5f4d6398a035712855b0745d2ec8454c47353e28
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Model.md
    blob: fa277d0d7644828d41dbe32d51676651e295991a
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Notifications.md
    blob: 2e7cf5d718aa3900c59429ebac929f4c39cec780
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Ordering.md
    blob: c72297e46657f25235bcf8590b4b0a59155a5412
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md
    blob: 32b4fca0bb10a41f8dc62e7277e945b362524336
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md
    blob: d485b96aa02de3cf3fd3a07c8b04160185bdb7b6
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md
    blob: 47a27edac7e0edf19793013ce009bf4592775a4c
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.md
    blob: 516b9608f20ee8b3ac170d52149c32dc6bcd496c
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md
    blob: d4111fdb2847ca8953a2a9b53ff177db69c87bbe
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
    blob: 3e269857aea94407aa1f90139e77d829c88f2d4c
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
    blob: 4fd88edc250644ca7ee72f17fb47df4b3dc2dc64
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
    blob: a41735713cf6da63f121027e3f6d3ef57936e5fa
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.md
    blob: 7e6e6b120d2e9d98035c0eef89b80d1c979be007
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.md
    blob: a8ca832ace2aadd9014f7589711c9bb6cfe2d0a8
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Support.md
    blob: d6ba44a3bcce2c2b1b6713076f1a9f0dccd74694
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-misc.md
    blob: 28ff20357a4c64b133fe77033aadc2e2e789f7e3
  - path: docs/atlas/modules/Packages-LillistCore-misc.md
    blob: 7a3c812a32768cbaed8e39c9ee9c003932524cc3
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Accessibility.md
    blob: ab3e82202d01c9fa6e0c73f77d110808a24220c7
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components.md
    blob: c4a41e22ac6c142cc1d822e60c101d34757746b7
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
    blob: cc9d4c3cda51581260dd2d7e4c41b25d2c140b90
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-DragReorder.md
    blob: 8d71618a097beb74e6f4a6fdb0d5e5796c932c95
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Editor.md
    blob: b7e1eda0e2a38efa996568b6436e03ad0e9b5df8
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Onboarding.md
    blob: a426ed4a048f4a9600cad90daf75c0604f2ed886
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-QuickCapture.md
    blob: edbf6d25f6ee2ab727da10dcf47981ebc9abadb7
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Recurrence.md
    blob: 3a7fa56f87fb3def9bd107fec35ca8ead5101d4b
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Settings.md
    blob: 93b8420819e766ed99a0559a7f4c476ba11e0538
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
    blob: c06f637e25002bb29fd4fc1b51d887b9a0ed4ce5
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
    blob: 0da94d0bbd3b7884c48aee1b6c1fdbf61d4859a8
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
    blob: fc239372d2032e299a27a34601d3a2e59d855f75
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
    blob: 1c698ac54f17945ef545113380c3dbbb44633d09
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
    blob: c0afa173e09bfac8a5390245b99c6b870bc55bdc
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
    blob: 551a62b0a84624728d7f67098179f31d3238306b
  - path: docs/atlas/modules/Packages-LillistUI-misc.md
    blob: 79ed1fdd62776dbb6c3d7ee3087e6ce7d4ee0115
  - path: docs/atlas/modules/Tools.md
    blob: c420e0553d61b8e7524cd72890457ceba44c38bc
  - path: docs/atlas/modules/root-misc.md
    blob: 161ee9b3b705e2d48811c02927709dc5d86180d3
scopes:
  - tree: Apps
    sha: a52266f8a34eb0c141b192f0f9c674ad466fc9b1
  - tree: Extensions
    sha: ff597562e13b8945b1b6ea230258f0d890b839c8
  - tree: Packages
    sha: a2eee3f227094065fb8f60cd34558bc40167ac81
  - tree: Tools
    sha: bad5b3cc8ef622898ae59320b9781f85949723b4
generator: cartographer/1
baseline: 8c52c45e4849ea5e0f0af3b7325eeb6e0cf3ede7
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
