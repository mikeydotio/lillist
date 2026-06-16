---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/Apps-Config.md
    blob: a7f331a45a0c4669e1129d3330e7f2fbd87e33f2
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
    blob: 7aabdb25873aeb1484ecee18813ab5161a5fdb3d
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Detail.md
    blob: 91101eaf371e182b58c77f841cb2f9ddbb09eb75
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings.md
    blob: 97764230a668cbaf80c59e37b2b91bedf20f0de0
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
    blob: c280c42dfb1ce46f13628d5e6115c846c5b90095
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
    blob: eb1540a63e11ef31664b0360b1e2ecb4837227ec
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Commands.md
    blob: 4d72bc161109aefb1a06a2f38ada4b8a4fd121b0
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
    blob: ba32dbb82c9e14612830ce8ca6ad126b623f0c48
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
    blob: ad0dcdfeac1f380daa2a96bb52496e5c88d75d5c
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-Detail.md
    blob: 699f847811d1bca6324043768f97e1f0c65e30fa
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-Sidebar.md
    blob: 6049288571cf199b38806f87bf9e538318f8d119
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-TaskList.md
    blob: af9529973d45d9a9b936094b933cb3fe19a111a1
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-misc.md
    blob: 0a5444a98428f0824474831c953d9e81219f9202
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-misc.md
    blob: a9072e7e34c3393fc24be9afbbd65660bf2e74f1
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
    blob: 96e2a7ac689f61fa791415b2ddfa5453fd3df441
  - path: docs/atlas/modules/Apps-misc.md
    blob: 56e2b103c244d178c09b5a55ece6ea62a48ae07b
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
    blob: ef672c3982c2e5e671875670f3a9e37406db59c2
  - path: docs/atlas/modules/Extensions-ShortcutsActions-Entities.md
    blob: bb8b40a344aa562bbd0aaf02310cd1843a5c3feb
  - path: docs/atlas/modules/Extensions-ShortcutsActions-misc.md
    blob: 6318c5e1cb3cf3c27268202ae8a954f8db2f57c8
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md
    blob: 536b732522d08b59a08560a15a4d52256079e796
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.md
    blob: 0fe242234f3a42582d24f8214d8d0b383a57ee71
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.md
    blob: 8a8e25c669be12e7d92e1baf9b9b605dd72798c7
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md
    blob: b36fb05057c5d5702d9dfcf9602cf12681a5b0f9
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md
    blob: 4318abca8e480e01d209210399d5c1dbaa645de8
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Diagnostics.md
    blob: 4a027a28ca1e21ba96664359d0f0d6840c1535ad
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
    blob: 4652f15b11c551ae3bc64cfaec1fb0c89217ca50
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
    blob: dfe378d42138b04d9487b94c4497bda4273e4d70
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md
    blob: 113d947c76cea39497208f875988c4ec6c687312
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Model.md
    blob: 1aec90482eadb6e846fc464e1778ae7bf7f7f0cd
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Notifications.md
    blob: 8870b40237d93e6be93889d56e8d8fdc4f69eebc
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Ordering.md
    blob: 1c418ab28d028510c333e5875eeb87dd33c2270f
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md
    blob: 566dc54ddee5d4dd35ff5e4cec47c8e9150e1f61
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md
    blob: 69b32b7fb1766587a0ce7d052cec024ad0d95c19
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md
    blob: 881974b62cf9a931642ba4db49a3f75a2fd44076
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.md
    blob: ef9f1f39669f7d2d288422f1d593268168d51d35
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md
    blob: 39de04642b9585e93061c21453c32f2045ea5c1b
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
    blob: c689025a02499aedb78771ac458db161ff994faa
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
    blob: eb7741d05cb2f35660e67d559d9b3f5eefbba7ca
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
    blob: 6f4977b03076f906606341b389640b882bad033e
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.md
    blob: 398a5cefaf88310b05ef4aea948e1d5f8fbf9570
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.md
    blob: 79a8d4396aacc07d4657bf5155491833d0b6df90
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Support.md
    blob: 5ac03316687520a424b2888b09d21c7ca6b32e48
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-misc.md
    blob: 2c0fdb14cb21435ef7619b7f3ad358e6f30a9c33
  - path: docs/atlas/modules/Packages-LillistCore-misc.md
    blob: e9c2f022fbcb46437d633715086fb922f6ff8a17
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Accessibility.md
    blob: b14fc445cd7862918bb3730b687f899b218981e1
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components.md
    blob: e20a219a889dc596ab9d88bb965151e8caa693b6
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
    blob: 69c5bb076d79a8674c42df89d2792f80d84ba0c8
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-DragReorder.md
    blob: afbd997ae2aa5c4cf7853a6985cc6f5f08853d57
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Onboarding.md
    blob: b7fd222a1cf17b867f74d454dea476fd96fd3cd3
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-QuickCapture.md
    blob: e7a9436e0f18a7aa108394c9208dae82534a11cc
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Recurrence.md
    blob: 4f7265b2833e8834460d3d02039baeaa5944a6f5
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Settings.md
    blob: 1ad69dbaf7214768333eb8a751a061a939b3767a
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
    blob: 7ce9e64d37635709eddd75de73b0c7e8a141b950
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
    blob: fb6e6bea6ab8774b42c1aa2a505212913a1ac920
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
    blob: 8af86995350d6f54611dedd7e7705c41797c04f4
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
    blob: 116c5278bb0ff3fb9088d97fa3128aeaf842c79e
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
    blob: 95a04c9fc8f9d6fc3d307b6a24a75ea137d2ecd0
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
    blob: 253de0b0f97e27066f5c9ee7e3ef229c35cf1528
  - path: docs/atlas/modules/Packages-LillistUI-misc.md
    blob: 6a564ce7efdcde47bbcc5bc0f40a22ec08f5fff5
  - path: docs/atlas/modules/Tools.md
    blob: e1c3deeaae042df1e703fff9a3d54242e18304a5
  - path: docs/atlas/modules/root-misc.md
    blob: a2e51894bcf57d113846b9e736824cc049c757df
scopes:
  - tree: Apps
    sha: 2598af9f0921ed7173763f1a0f4f618e0e85cfaa
  - tree: Extensions
    sha: 96c33867d5cc70171ae43dffc775cd4ffcc4bdb0
  - tree: Packages
    sha: 2a66e34c8ed9a030e9e6e44fbb5d54ee039acddd
  - tree: Tools
    sha: bad5b3cc8ef622898ae59320b9781f85949723b4
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
---

# Architecture

## System shape

Lillist is an Apple-only task manager (Swift 6, SwiftUI, Core Data over
`NSPersistentCloudKitContainer`) built as a strict four-layer dependency stack
fanning out from one package. **`Packages/LillistCore`** is the data/services
core: hand-written `@NSManaged` entities, value-type stores (`TaskStore` et al.),
the predicate rule engine, recurrence expander, notification scheduler, sync-mode
machinery, crash reporter, diagnostics, link unfurler, export/import, the shared
`CLIBridge` verb layer, and the `lillist` CLI executable. **`Packages/LillistUI`**
sits above it: a cross-platform SwiftUI library of pure-presentation components,
Rainbow Glass design tokens, the drag-reorder engine, recurrence/sync/settings
surfaces, and the iOS screen shells. Above both sit two app targets — **`Apps/Lillist-iOS`**
and **`Apps/Lillist-macOS`** — each a thin shell that builds an `@Observable`
`AppEnvironment`, owns lifecycle/`@State`/navigation, and delegates rendering to
LillistUI and data to LillistCore. Two **`Extensions/`** (Share sheet, App Intents)
are independent processes reaching the same store, and **`Tools/`** + repo-root
config govern build/CI.

The load-bearing seam is the **DTO boundary**: no `NSManagedObject` ever escapes
LillistCore — every public store API returns Sendable value records, enforced at
each store's `record(from:)`. The second seam is the **container/presenter split**:
LillistUI screens are state-free pure views fed by app-target wrappers, which is
what lets snapshot/tour tests render real screens with frozen mock data. The CLI,
both apps, and both extensions all converge on `CLIBridge` handlers (or stores
directly) so business logic is written once. LillistCore never imports LillistUI
or any app; dependencies point strictly downward toward the data core.

## Module relationships

- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Persistence (owns)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (owns)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-CrashReporting (owns)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Notifications (owns)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Diagnostics (owns)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-Onboarding (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-CrashReporting (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Apps-Lillist-iOS-Sources-App (reads)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-iOS-Sources-Detail -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-Detail -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Apps-Lillist-iOS-Sources-Settings -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Apps-Lillist-iOS-Sources-Settings -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-misc (owns)`
- `Apps-Lillist-macOS-Sources-misc -> Apps-Lillist-macOS-Sources-Views-misc (calls)`
- `Apps-Lillist-macOS-Sources-misc -> Apps-Lillist-macOS-Sources-Hotkey (owns)`
- `Apps-Lillist-macOS-Sources-Views-misc -> Apps-Lillist-macOS-Sources-Views-Sidebar (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc -> Apps-Lillist-macOS-Sources-Views-TaskList (calls)`
- `Apps-Lillist-macOS-Sources-Views-misc -> Apps-Lillist-macOS-Sources-Views-Detail (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Views-TaskList -> Packages-LillistUI-Sources-LillistUI-DragReorder (owns)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistUI-Sources-LillistUI-QuickCapture (owns)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Extensions-ShortcutsActions-misc -> Extensions-ShortcutsActions-Entities (owns)`
- `Extensions-ShortcutsActions-Entities -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-misc -> Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 (owns)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-ManagedObjects (owns)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Persistence (owns)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (owns)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects -> Packages-LillistCore-Sources-LillistCore-Recurrence (reads)`
- `Packages-LillistCore-Sources-LillistCore-Rules -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export -> Packages-LillistCore-Sources-LillistCore-Persistence (reads)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistCore-Sources-LillistCore-Persistence (reads)`
- `Packages-LillistCore-misc -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-DragReorder (owns)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence -> Packages-LillistCore-Sources-LillistCore-Recurrence (owns)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistCore-Sources-LillistCore-Diagnostics (emits)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistUI-Sources-LillistUI-misc -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistUI-misc -> Packages-LillistCore-misc (reads)`
- `Apps-misc -> Apps-Config (reads)`
- `Apps-Lillist-iOS-misc -> Extensions-ShareExtension-iOS (owns)`
- `Apps-Lillist-iOS-misc -> Extensions-ShortcutsActions-misc (owns)`
- `Tools -> Apps-Config (writes)`
- `root-misc -> Packages-LillistCore-misc (calls)`

## Data flow

A representative write — **create a task via Quick Capture on iOS** — moves down
the layers: `QuickCaptureDialogHost` (iOS app) runs `LillistUI.QuickCaptureParser`
to split raw text into title/`#tags`/`^date`, resolves the date through
`LillistCore.RelativeDateResolver`, then calls `TaskStore.create(...)`. The store
validates the title via `Validators`, assigns the next `FractionalPosition`, writes
the `LillistTask` managed object inside `viewContext.perform`, saves, and — outside
the perform block — reconciles notifications (`NotificationScheduler.reconcile`),
records a crash breadcrumb, and emits a `DiagnosticSink` event. It returns a
`TaskRecord` DTO; the app re-fetches through `TasksView.reload`. The same write
from another process (CLI `lillist add`, a Shortcuts `AddTaskIntent`, or the Share
extension) enters through `CLIBridge.AddHandler` / `GatedPersistenceResolver` over
the App-Group store, so the rules and tag-matching converge.

A representative chain reaction — **closing a recurring task** — shows the
side-effect fan-out: `TaskStore.transition(id:to:.closed)` logs a status journal
entry, then calls `RecurrenceSpawner.spawnIfNeeded`, which reads the task's
`Series.rule`, advances the date through `RecurrenceExpander` (DST-correct via
`Calendar`), and mints the next instance — all inside one `perform`/`save`. Reads
flow the other way: a smart filter compiles a `PredicateGroup` to an `NSPredicate`
(`SmartFilterStore` -> `NSPredicateCompiler`) for live fetches, or evaluates it in
pure Swift (`SwiftEvaluator`) over a `TaskSnapshot`, the two kept behaviorally
identical by a parity fixture suite.

## Key invariants

- **No `NSManagedObject` escapes LillistCore.** Stores return value DTOs; enforced at `TaskStore.record(from:)` (`Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift:975`).
- **Hand-written `@NSManaged` subclasses, no codegen.** Model entities use `codeGenerationType="manual/none"` (`Packages/LillistCore/README.md:26`); subclasses in `ManagedObjects/`.
- **Date math through `Calendar`, never `addingTimeInterval`.** `RecurrenceExpander` is canonical (`Packages/LillistCore/Sources/LillistCore/Recurrence/RecurrenceExpander.swift:9`); the one exception is the absolute-seconds `afterCompletion` rule.
- **Twin predicate evaluators stay in lockstep.** `NSPredicateCompiler` and `SwiftEvaluator` must agree (`Packages/LillistCore/Sources/LillistCore/Rules/SwiftEvaluator.swift:174`).
- **All targets share App Group `group.io.mikeydotio.Lillist`.** Single store path across app/Share/Shortcuts/CLI (`Apps/Lillist-iOS/Lillist.entitlements:13`, `Apps/Lillist-macOS/Lillist.entitlements:11`).
- **Persisted enum raw values are immutable.** `Status`/`NotificationKind` cases never reorder or drop (`Packages/LillistCore/Sources/LillistCore/Model/Status.swift:6`).
- **Strict concurrency on LillistCore + LillistUI source targets; warnings-as-errors.** (`Packages/LillistCore/Package.swift:27`, `Packages/LillistUI/Package.swift:27`).
- **Headless callers consult `MigrationGate` before opening the store.** Aborts with `storeUnavailable` mid sync-mode swap (`Packages/LillistCore/Sources/LillistCore/Sync/MigrationGate.swift:27`).
- **Sync-mode change is a store-level remove+re-add on one long-lived container.** Never a re-instantiation (`Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift:139`).
- **LillistUI screens are pure presentation; app targets own state.** Container/presenter split so tour tests render with mock data (`Packages/LillistUI/Sources/LillistUI/iOS/Screens/TasksScreen.swift:14`).
- **CLI/Shortcuts/apps share `CLIBridge` business logic.** Commands and intents are thin wrappers (`Packages/LillistCore/Sources/LillistCore/CLIBridge/CLIBridge.swift:9`).

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
