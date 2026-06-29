---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/Apps-Config.md
    blob: 6552414d63fa0af6b60520ec9f3f791faf553b06
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
    blob: 9aa6cf81686eee815fdc039571a930751abad267
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings-Pages.md
    blob: fb9e61a06f7bfbdf194435543d57ab2ff913dc35
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings-misc.md
    blob: 3fd5204c348e22ea40976e8b8f8ea0dfb21dd981
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
    blob: a9a6811f500af2ecf51d9fc9a84a62721e140f59
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
    blob: 80fcebcda124dcb81fcf6590c9a0b0db3fcd768f
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
    blob: a1ace49c8bc6b6dfe2995bb6f0484842b1ae75cd
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
    blob: 30689be5aa98dd84b57b3cf848e110217a7b9a21
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-chunk-1.md
    blob: 45004817fee3220224b06b252c0ea4c9db9fdf73
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-chunk-2.md
    blob: 324369c91444ecd343a517aefc962ef50e19572a
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
    blob: 8717684e25ea017ded7147e370f1f0ea6e00d41d
  - path: docs/atlas/modules/Apps-misc.md
    blob: c4f968967be989f8c7883dc252bfdbb79750023a
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
    blob: 64158530867522bc41ba715620828fc270974d96
  - path: docs/atlas/modules/Extensions-ShortcutsActions-Entities.md
    blob: 28c4ee5026f472e2ce99920335ff6caf0f47800e
  - path: docs/atlas/modules/Extensions-ShortcutsActions-misc.md
    blob: 30c14c239932a90a73e91baeada607477965d2ee
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Backup.md
    blob: 4fa75640cb5a8d5a4678531754af07795bfcf32e
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.md
    blob: b75290bc341689b6e633f32dd7a5c7db1c75b019
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2.md
    blob: 5e0de9bf6c0efd5bfef0261f06dfde37eb2b94d5
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers.md
    blob: 512661ebfbdde98901e8af27a73ef60a1b082573
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CLIBridge-misc.md
    blob: 631f84aae35cd2d6c3f92aa88f3d023d52b355bb
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-CrashReporting.md
    blob: c07b6b7fd12e60a49d04a7767489f721dea62998
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Diagnostics.md
    blob: 400ea5ecf2cdfd1f92160c2e4850364ef9a7a131
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
    blob: af52f7f97a48e9b5113ebacf0802c54b6af0cef1
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
    blob: c0e425bdea90068b9d55beb2af3b24a5e89066e8
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-ManagedObjects.md
    blob: 1301d3845df8a65717d861bcc6b0c732a78272cb
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Model.md
    blob: f34eae3db619a188f1614729bc613d0a845ac789
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Notifications.md
    blob: a785624e5693da0228034a3ef816721d8115b722
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Ordering.md
    blob: b7e9a58ca1abddb2bcffe1bea2327f8561c443ca
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Persistence.md
    blob: e36497f2c5b6e4c6673896791ed0f1e243964500
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Recurrence.md
    blob: f7ba6b39357df54710c078afc000cf20fcfd9c23
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Reminders.md
    blob: e9c87496b4ebb156593707079e79a98826f758c5
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Rules.md
    blob: 9ab25f3846d42f8d90106846f5cb6db438e51f20
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.md
    blob: 97af74e1cb3eed6948f9d704c975d6e6fc215dc9
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.md
    blob: dd6a943e27442623ddc0f14f817cbfb97edc2197
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
    blob: 30e7d41bc7c2723906a86e42a70736f92cb93c27
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
    blob: a83688e96b2e443500e169ea2f78a6e46319c433
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
    blob: 2e87e4745177305a58d5230ca6cd17fcbb2b9402
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1.md
    blob: ca5e752339750a98f5e436396099b6347476e3c9
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.md
    blob: 5c41d13f70203e3cc9ca8b195f1f766efe6073f5
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-Support.md
    blob: 0dcc239856b432f8efd2e58cbaa294501264c3c0
  - path: docs/atlas/modules/Packages-LillistCore-Sources-lillist-cli-misc.md
    blob: 06446e59d1aa66e69186f9730b6bef48ec5dfb1f
  - path: docs/atlas/modules/Packages-LillistCore-misc.md
    blob: 588f3391f1fb7ae80060daca5415edefe6aa6aef
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Accessibility.md
    blob: 9e6348f1defc3c1b8a0a5859aa4721d5723648cd
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components-chunk-1.md
    blob: 6d63d4dbc253bf22eb5b04139a0e994b2a6457b0
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components-chunk-2.md
    blob: 3005025693c3d9e69af612d524da99895b673448
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
    blob: 7314f89c765aab151cd52c1696e5d8af4edf7b31
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-DragReorder.md
    blob: 26e81ab0b4919457957bfb85a150de2f0a4a7922
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Editor.md
    blob: c8bf0d2b7c9818c6f288f83a555259b780be97b9
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Onboarding.md
    blob: 2ad1a823665e68db7c51183387d1ff5edd7ad861
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-QuickCapture.md
    blob: edf336a81dfe8916e4cf37b82614d45eab05c9ac
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Recurrence.md
    blob: a6b11ff49ed0c2a5decda9c659b16a52b0bd5929
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Settings.md
    blob: 594529bc5bf3cc2582b1fc9d02e0aa5861008adc
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Status.md
    blob: fcb4925733f1b1d7d5f5f69ed8e8a048a9588b0c
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
    blob: 3556d904e2096d0c80eec5ae59ed15fea2feecd3
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
    blob: dbdd2ef6d80defb110cf3d4b4a9f28ba3247c744
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
    blob: 95ace458c507db8b534517018c6072525868362a
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
    blob: 58b45a6d4032f1e4dc81428c3fd94c0499edc750
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
    blob: b596496055fd764bac016c2c5e88306c3adcab33
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
    blob: 30256dcab255311de2312c463f8ded7d7cef589a
  - path: docs/atlas/modules/Tools.md
    blob: 12f0da0a05abe1c8c1610b46b7601bd806de13ed
  - path: docs/atlas/modules/root-misc.md
    blob: 2b6c8885260802a794afbdbd3eb1f5b86dd6f057
scopes:
  - tree: .claude
    sha: c0048318f41119751eb2c47fac6b554968263749
  - tree: .deployit
    sha: 3844b423350f82f7876cac0c3cab827ba467d13b
  - tree: .github
    sha: 92656f67986f73d0c6424d5ea383fe77faab8981
  - tree: .semver
    sha: 5c304c73e25e543188c0621d53e93485ab8a88c9
  - tree: Apps
    sha: 20592a1d7093845751e84c34168e1618859e81ca
  - tree: Extensions
    sha: 7cab90c6c86441df34918c362dcae31865c3f149
  - tree: Lillist.xcworkspace
    sha: 4ab8ae97476a5eee945c84abee40f224c3608d73
  - tree: Packages
    sha: 4333c8c3496a1b88c57430b382be6dde5054f30c
  - tree: Tools
    sha: 5587bf16d839d26dd87051c9c2ee0d382492dc74
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Architecture

## System shape

Lillist is a strictly layered Apple-platform app. Four layers stack in one direction — LillistCore, LillistUI, the two app targets (iOS and macOS), plus lateral extensions and CLI that reuse core without touching UI. LillistCore owns the data model (Core Data entities, NSPersistentCloudKitContainer), all store APIs (TaskStore, TagStore, JournalStore, etc.), the sync-mode state machine and CloudKit plumbing, recurrence expansion, notification scheduling, and the CLIBridge verb layer. LillistUI is a cross-platform SwiftUI library sitting on top of LillistCore; it supplies the design-token theme (Rainbow Logic / Liquid Glass), pure-presentation screen structs, the shared Settings primitives including ICloudSyncSettingsSection, sync-modal surfaces (SyncSheetRoute + six sheet views), the Status translation layer (CloudKitSyncStatusAdapter → SyncIndicatorMonitor), task-row components, editor, drag-reorder, quick-capture, and crash-reporting UI. The two app targets (Apps/Lillist-iOS, Apps/Lillist-macOS) are thin wrappers: they own AppEnvironment, @State, navigation destinations, and the env-coupled Settings/Preferences sections that wire live stores to LillistUI's state-free presenters. The Share Extension and Shortcuts Actions Extension sit laterally — they import LillistCore directly and are gated by MigrationGate.

The seams are load-bearing. No NSManagedObject crosses LillistCore's boundary — every public store API returns a value-type DTO (TaskRecord, TagRecord, etc.). LillistUI screens are stateless presenters: they receive data and action closures via init, own no @State, issue no .task calls, and read nothing from AppEnvironment — making them fully renderable by the snapshot-test tour runner with frozen mock data. The app-layer wrappers own all lifecycle (@State, .task, environment reads) and all navigationDestination handlers that reference app-target types LillistUI cannot import.

The sync and Settings surfaces follow this pattern explicitly: the shared ICloudSyncSettingsSection (LillistUI) and the complete sync-modal sheet set (LillistUI/Sync) are pure presenters; the env-coupled iOS ICloudSyncSection and macOS ICloudSyncPane own the MigrationCoordinator calls, SyncSheetRoute routing slot, and TaskStore.syncCounts() polling that feeds the ViewState snapshots the presenters render. CloudKitSyncStatusAdapter (LillistUI/Status) bridges the async SyncStatusMonitor stream from LillistCore onto the @Observable SyncIndicatorMonitor protocol that all UI surfaces bind to; the app layer overlays account-level PauseReason atop the adapter's output.

## Module relationships

- `Apps-Lillist-iOS-Sources-App -> Apps-Lillist-iOS-Sources-misc (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Backup (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Reminders (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2 (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-CrashReporting (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-Status (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-App -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Apps-Lillist-iOS-Sources-Settings-misc (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Apps-Lillist-iOS-Sources-Settings-Pages (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Backup (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Reminders (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Apps-Lillist-iOS-Sources-Settings-misc (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Editor (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Onboarding (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Status (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (calls)`
- `Apps-Lillist-iOS-Sources-misc -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Apps-Lillist-macOS-Sources-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistUI-Sources-LillistUI-Editor (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Apps-Lillist-macOS-Sources-Hotkey -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Backup (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Reminders (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-Preferences -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Apps-Lillist-macOS-Sources-Preferences (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Apps-Lillist-macOS-Sources-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Backup (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Reminders (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-CrashReporting (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Editor (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Onboarding (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Status (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (calls)`
- `Apps-Lillist-macOS-Sources-chunk-1 -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Apps-Lillist-macOS-Sources-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Editor (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Status (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (calls)`
- `Apps-Lillist-macOS-Sources-chunk-2 -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Reminders (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Extensions-ShareExtension-iOS -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Extensions-ShortcutsActions-Entities -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Extensions-ShortcutsActions-misc -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Extensions-ShortcutsActions-Entities (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Backup -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Export (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-misc -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistCore-Sources-LillistCore-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistUI-Sources-LillistUI-Editor (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export -> Packages-LillistCore-Sources-LillistCore-Backup (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export -> Packages-LillistCore-Sources-LillistCore-ManagedObjects (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Export -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistCore-Sources-LillistCore-LinkPreview -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-ManagedObjects -> Packages-LillistCore-Sources-LillistCore-Model (calls)`
- `Packages-LillistCore-Sources-LillistCore-Model -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Notifications -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Extensions-ShortcutsActions-misc (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Persistence -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Recurrence -> Packages-LillistCore-Sources-LillistCore-ManagedObjects (calls)`
- `Packages-LillistCore-Sources-LillistCore-Reminders -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Reminders -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Rules -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-ManagedObjects (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Rules (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistCore-Sources-LillistCore-misc (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-ManagedObjects (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Extensions-ShareExtension-iOS (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Persistence (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-2 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-1 -> Packages-LillistCore-Sources-lillist-cli-Support (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Renderers (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2 -> Packages-LillistCore-Sources-lillist-cli-Support (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistCore-Sources-lillist-cli-misc -> Packages-LillistCore-Sources-lillist-cli-Support (calls)`
- `Packages-LillistUI-Sources-LillistUI-Accessibility -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Extensions-ShareExtension-iOS (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-misc (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2 -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Packages-LillistUI-Sources-LillistUI-Components-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting -> Packages-LillistCore-Sources-LillistCore-CrashReporting (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistCore-Sources-LillistCore-Diagnostics (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistCore-Sources-LillistCore-Notifications (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistCore-Sources-LillistCore-Sync-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistUI-Sources-LillistUI-Status (calls)`
- `Packages-LillistUI-Sources-LillistUI-Editor -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-QuickCapture -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence -> Packages-LillistCore-Sources-LillistCore-Recurrence (calls)`
- `Packages-LillistUI-Sources-LillistUI-Recurrence -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Settings -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Settings -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistUI-Sources-LillistUI-Settings -> Packages-LillistUI-Sources-LillistUI-iOS-misc (calls)`
- `Packages-LillistUI-Sources-LillistUI-Status -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Sync -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Recurrence (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2 -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-2 -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistCore-Sources-LillistCore-Ordering (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Apps-Lillist-macOS-Sources-Hotkey (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistCore-Sources-LillistCore-LinkPreview (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-Accessibility (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-Components-chunk-2 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-DragReorder (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc -> Packages-LillistUI-Sources-LillistUI-iOS-Tasks (calls)`

## Data flow

Consider a user toggling iCloud Sync off from iOS Settings. The action originates in ICloudSyncSection (Apps-Lillist-iOS-Sources-Settings-misc), which holds an ICloudSyncModalsModel and a SyncSheetRoute? routing slot. The toggle's onChange calls handleToggle(on: false), which sets route to .disable via SyncSheetRoute.afterToggle(on:) (LillistUI/Sync). The .sheet(item: $route) bound in the host ICloudSyncPage presents SyncDisableConfirmationSheet (LillistUI/Sync) — a pure-presentation struct receiving two closures. The user chooses "Sync First"; the closure calls ICloudSyncSection.triggerDisable(strategy: .syncFirst), which invokes runMigration: it subscribes MigrationCoordinator.progressStream into route (setting it to .progress(phase)), then calls coordinator.beginDisable(strategy:) on the @MainActor MigrationCoordinator (LillistCore/Sync-chunk-1). MigrationCoordinator.runMigration, the 170-line core state machine, writes journal heartbeats at each phase, cancels pending notifications via NotificationScheduler (LillistCore/Notifications), waits for the quiesce gate via SyncStatusMonitor (LillistCore/Sync-chunk-2), tears down the CloudKit-backed store, rebuilds the local-only store via PersistenceController (LillistCore/Persistence), restores notifications, and writes the new SyncMode to SyncModeStore (LillistCore/Sync-chunk-1). Each phase boundary emits a MigrationPhase via progressStream, which runMigration's subscriber converts to a new .progress(phase) route value; the SwiftUI binding updates SyncMigrationProgressSheet (LillistUI/Sync) in place — the sheet's .progress case holds a constant id so it updates rather than dismisses. On .completed, runMigration sets route to nil, dismissing the sheet. Meanwhile CloudKitEventBridge (LillistCore/Sync-chunk-1) stops receiving eventChangedNotification events; CloudKitSyncStatusAdapter (LillistUI/Status) receives the final status from SyncStatusMonitor and publishes a new SyncIndicator to the app's sync dot. ICloudSyncSection.refreshCounts() — called on every indicator change — polls TaskStore.syncCounts() (LillistCore/Stores-chunk-2) and writes the result into ViewState, causing ICloudSyncSettingsSection (LillistUI/Settings) to render the updated local/mirrored counts.

<!-- atlas:index-facts -->
- Layers: LillistCore->LillistUI->apps; CLI/extensions reuse core
- No NSManagedObject leaves LillistCore; stores return DTOs
- TaskStore: sole async gateway for task CRUD/reorder/status
- Date math via Calendar; RecurrenceExpander canonical
- Smart filters: NSPredicateCompiler + SwiftEvaluator parity
- App Group group.app.lillist; gated by MigrationGate
- LillistUI screens state-free; apps own @State/nav
- MigrationCoordinator: @MainActor sync-mode FSM
- CloudKitSyncStatusAdapter bridges sync to UI
<!-- /atlas:index-facts -->
