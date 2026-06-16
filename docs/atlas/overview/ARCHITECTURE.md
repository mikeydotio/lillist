---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/Apps-Config.md
    blob: 2493d2a6c36b174f49d935d5804cad1240e50cc6
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
    blob: 209180ded87dadc7058cb0d9795e3bf3c611b822
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Detail.md
    blob: 47f9edd9b02f549a1566126a13adb5a93ce6b0f2
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings.md
    blob: d078d39850a20a1d0bbfde0ae3b880b8555766ae
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
    blob: 70b06f133befcd6316dbf0c3a8e3d1482e048062
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
    blob: a5f554d43591f50a79f72f2cb8cb2939e29af771
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Commands.md
    blob: a85a427908f399e8a83ee6c7551818e11bc50d58
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
    blob: 95622695e076cf1f6a43f9c0f39602902a103dfc
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
    blob: 3ecc47bab5e03f12e0f2df5b4a6c007440b6c287
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-Detail.md
    blob: fc509e85abd799c83d203e682f8b9bb07652ce4c
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-Sidebar.md
    blob: 35d0fe41396e4925eeb700c26719b33c419ba4d2
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-TaskList.md
    blob: fd076008120f3759a0c27fa36576718426818cee
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Views-misc.md
    blob: 555161b72c2877b8e3db1fe6b6e8e40acc983ecc
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-misc.md
    blob: bc6b999b91ded693ff45588fc6bfe33bc76d1fe2
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
    blob: 0c9b60af342a94a5d27b5be7a392805e58105b40
  - path: docs/atlas/modules/Apps-misc.md
    blob: ea1b47c8ef9a4b9f414e6439901c8fc02190571b
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
    blob: 3ec476e1b80c8dde3dd33a0b125bde9b424f4724
  - path: docs/atlas/modules/Extensions-ShortcutsActions-Entities.md
    blob: 6ad9be035a2028be15404a21b5b7306ed0c06000
  - path: docs/atlas/modules/Extensions-ShortcutsActions-misc.md
    blob: cb2fabfd2929196badf00d6d8246fcad1a3d51f9
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md
    blob: 3b5e49bfa3b9756f125d19ec19d2c07c71eeeb59
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.md
    blob: 29638a357806b6327af59e60acb064d303dc18da
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.md
    blob: b746165d7a39bcd8203d52451576e5963f2c87d4
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md
    blob: 95c063188c265161cc59cfdb6d281fb4e82efce5
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md
    blob: 3c6c353d86ce0938c33698def4c7682aa9828fce
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Diagnostics.md
    blob: c1af48d0ede0afdfe10cb5ded667fdc13b1c821e
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
    blob: a4d3eb7011cf4542aa03b89614da153e58c4791f
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
    blob: b12b9284338d71ba1129392d26b127b0008e1cca
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md
    blob: 54244fe9091f1765fd057ce584d593c957b107d6
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Model.md
    blob: 141f755443f5de453105f3478b19a04e04759bcb
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Notifications.md
    blob: 62360d8b4a32da4ae4121cb3acd87b8658147095
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Ordering.md
    blob: 82b9e9782130564ef63a4760171ebd0db24d7659
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md
    blob: e08f71adeabc4a9460b0f6b1192479e53ff1a371
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md
    blob: ef87fee0b27cff55672ca235d6c78d5d1eae2dea
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md
    blob: 44fbc7477ef9b38586b8c44b1d72cdff154ecea6
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.md
    blob: 7d6ff9089e6efb7d7b3dbc6429995ae0d271f3a7
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md
    blob: a0607b6ced5a955b4f7d2085a4e22be9f4c3c3ca
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
    blob: 5a6c083eef548fc5381b21b9eac8523ba36d05f3
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
    blob: c586669c68dec6919f77fda23f3e4f8c18b52807
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
    blob: f77d18abcd13660b300837c36a3894666a8ca0ae
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.md
    blob: 52b8683901fcb65fe22198518401b3beb0729b02
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.md
    blob: c21db51348f22958e05ac60d34a9b13d39b09907
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Support.md
    blob: 1503d9a9df72b20ef72b556bfc62e83002ac9ae8
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-misc.md
    blob: 9811e041522cc3485e58b24d6c5f3e95990dd812
  - path: docs/atlas/modules/Packages-LillistCore-misc.md
    blob: dd4f217ced909202890f0278af7209da643a93bc
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Accessibility.md
    blob: 70f196443e48c9cb6d4d01335d12cda7776de08c
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components.md
    blob: 19b2f965dab22b55a4fed2c345f61980d897f2ce
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
    blob: c2ca8fa2490b890914cb846985700e4a9f7375d9
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-DragReorder.md
    blob: c7e86afba9f4f890b7389906f337519a70d56b6d
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Onboarding.md
    blob: b373140d2204e5d042d3fc2b0ddc867b571f34b5
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-QuickCapture.md
    blob: 1fd7909112baa3bf2d1a4bdaadfb6c5d75794943
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Recurrence.md
    blob: 617c703eaabcca611c997ea223e26937e16b3f53
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Settings.md
    blob: b8bbb925bbcd14798166bc715a36a5a76089cc68
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
    blob: aee273972d2a0d167d95cb07b0ae1aa2979bb2e2
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
    blob: 4b0cb0750a00aba7c8028059d8e1fc49e62b10bf
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
    blob: d112c48ad4f1ff66563ca4936774b6cfb321e20e
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
    blob: 5e2ca25c816f0f29d8f16f5bfc6f2fe1dddd316d
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
    blob: 4f4b6f01f08674ffc10809c7bf515db54519a5a4
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
    blob: b30c60a00e420c79948e34a0e6c74b84de5997cd
  - path: docs/atlas/modules/Packages-LillistUI-misc.md
    blob: 0716ead932138a0b1076e2ed62970478b03dcb42
  - path: docs/atlas/modules/Tools.md
    blob: dfaf03b2897e7f3e285ae68dec24083f1be33096
  - path: docs/atlas/modules/root-misc.md
    blob: b3532351462cc8e40b9dc37be77b0654b0b720bd
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
baseline: f01d150d9612ba87d7a01645e22fe452c9cfe995
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
