---
module: overview/ARCHITECTURE
summary: "System architecture and cross-module relationships"
sources:
  - path: docs/atlas/modules/Apps-Config.md
    blob: 667daf368c61159472633c19641d221103e90374
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-App.md
    blob: f8ae4c59d047918649edfcee00d4329576e1062a
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings-Pages.md
    blob: 9679fdd24750f87aa6293930b3a951a12dd3552e
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-Settings-misc.md
    blob: 0897b5ff0259968a9f79e1ad118391fa1d49d20a
  - path: docs/atlas/modules/Apps-Lillist-iOS-Sources-misc.md
    blob: a9a6811f500af2ecf51d9fc9a84a62721e140f59
  - path: docs/atlas/modules/Apps-Lillist-iOS-misc.md
    blob: 508c855b9c66d2b82fe08484b589053a5885ac36
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Hotkey.md
    blob: a1ace49c8bc6b6dfe2995bb6f0484842b1ae75cd
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-Preferences.md
    blob: daf0770a69528e8dbca2ae1b9b71762875010ba4
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-chunk-1.md
    blob: a25a0b31c5af556b1e9c9b36e2be0907e9392be4
  - path: docs/atlas/modules/Apps-Lillist-macOS-Sources-chunk-2.md
    blob: 324369c91444ecd343a517aefc962ef50e19572a
  - path: docs/atlas/modules/Apps-Lillist-macOS-misc.md
    blob: 8717684e25ea017ded7147e370f1f0ea6e00d41d
  - path: docs/atlas/modules/Apps-misc.md
    blob: 05c690edad20c8730c13459a5915d9a45f386a4d
  - path: docs/atlas/modules/Extensions-ShareExtension-iOS.md
    blob: dffa9ab173f51344575d4df4a93c3d475025fc7d
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
    blob: 9fa79a048b56ac11f449df91a25c2ceea2d75699
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Export.md
    blob: af52f7f97a48e9b5113ebacf0802c54b6af0cef1
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-LinkPreview.md
    blob: 5035e3e77c275075accb6804d562b50dbf1e6ea0
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
    blob: 290460ede8a4d5803231caf1f329183cac850567
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-1.md
    blob: 6f96784b30e00c05261a9759d18659a4244acb2c
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-Sync-chunk-2.md
    blob: bafa6b35528efbf2cf614fcfe44ed95c4ed71613
  - path: docs/atlas/modules/Packages-LillistCore-Sources-LillistCore-misc.md
    blob: 5835ee5601d2598fcae3085eaea995d64ad98084
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
    blob: 0246c12d5e8cc631f5090c8bea88e742f8f19d4b
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Components-chunk-2.md
    blob: 3005025693c3d9e69af612d524da99895b673448
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-CrashReporting.md
    blob: 904cb5cf3a6a31f029d25c57180714e5c4223836
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
    blob: f19c98bbef86e9e6398873876d59273c8818bc0e
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Status.md
    blob: 13ee85982b456da78f5f40b6168f3ff21dd05043
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Sync.md
    blob: b36385ef11b6f9d2245adc3f048bee3d5d439630
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.md
    blob: dbdd2ef6d80defb110cf3d4b4a9f28ba3247c744
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.md
    blob: 95ace458c507db8b534517018c6072525868362a
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-Tasks.md
    blob: 58b45a6d4032f1e4dc81428c3fd94c0499edc750
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-iOS-misc.md
    blob: f0537dd3f5b046b5ac34cd344ee4b6b151e4ab4f
  - path: docs/atlas/modules/Packages-LillistUI-Sources-LillistUI-misc.md
    blob: ff984258bc034a9a24c762bd71a55bd7d0584f23
  - path: docs/atlas/modules/Tools.md
    blob: 12f0da0a05abe1c8c1610b46b7601bd806de13ed
  - path: docs/atlas/modules/root-misc.md
    blob: 4af2e83b33423ab80059ddcfb0dda30c73f313a0
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
    sha: 76becee23e9f0845038349b19eb10cf05916a44c
  - tree: Extensions
    sha: 7cab90c6c86441df34918c362dcae31865c3f149
  - tree: Lillist.xcworkspace
    sha: 4ab8ae97476a5eee945c84abee40f224c3608d73
  - tree: Packages
    sha: 1b098cab65ec27a945524c2a1b5dc4716b51ed59
  - tree: Tools
    sha: 5587bf16d839d26dd87051c9c2ee0d382492dc74
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Architecture

## System shape

Lillist is organized as a strict unidirectional dependency stack. LillistCore sits at the foundation and owns the entire data layer: eight hand-written @NSManaged entity subclasses, five primary stores (TaskStore, AttachmentStore, JournalStore, SeriesStore, SmartFilterStore), the NSPersistentCloudKitContainer lifecycle, sync-mode state machine, notification scheduling, recurrence expansion, backup, diagnostics, and the CLIBridge verb library. Every public API on LillistCore returns value-type DTOs — no NSManagedObject ever crosses the package boundary. LillistUI sits above LillistCore and provides a cross-platform SwiftUI component library whose views are pure presenters: all data arrives through init parameters and all actions leave through closures, with no @State or AppEnvironment coupling anywhere inside the package. iOS and macOS app targets sit at the top, each assembling an AppEnvironment object graph that wires LillistCore stores and services into LillistUI screens.

Two parallel tracks consume LillistCore directly without going through an app target. The lillist CLI defines AsyncParsableCommand verb structs that open the App-Group-shared Core Data container via CLIBridge.StoreLocator, then delegate every domain operation to CLIBridge handler namespaces — the same handler enums that Shortcuts App Intents call from their perform() bodies. The ShareExtension-iOS and ShortcutsActions extensions open the shared store through IntentSupport.makePersistence(), which passes through MigrationGate so headless opens never race a live sync-mode swap. CLIBridge is the explicit seam that keeps business logic deduplicated across the CLI and Shortcuts surfaces.

At the infrastructure layer, a three-level xcconfig cascade in Apps/Config decouples signing identity, build number, and distribution URLs from the committed pbxproj; two xcodegen project.yml specs generate the pbxproj files from that config. The Rainbow Glass design system lives entirely in LillistUI/Theme, providing a single #available gate for iOS/macOS 26 Liquid Glass with accessibility-respecting degradation. CI enforces pbxproj drift as a post-push gate, ensuring the generated files stay in sync with their yml sources.

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
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-Settings (calls)`
- `Apps-Lillist-iOS-Sources-Settings-Pages -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1 (calls)`
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
- `Apps-Lillist-iOS-Sources-Settings-misc -> Packages-LillistUI-Sources-LillistUI-Sync (calls)`
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

Trace: user adds a task via iOS Quick Capture.

1. User taps the FAB (LillistUI/iOS-misc: FloatingActionButton inside TasksScreen). The QuickCaptureOverlayModifier, hosted by TaskEditorHost in Apps-Lillist-iOS-Sources-misc, presents QuickCaptureDialog.

2. As the user types "Buy milk #groceries ^tomorrow", QuickCaptureParser.parse (LillistUI/QuickCapture) splits the free-text string into a title, a #tag token, and a ^date token, updating the live preview on each keystroke.

3. The user taps Add. The app-target wiring in Apps-Lillist-iOS-Sources-misc invokes TaskEditorModel.addTask() (LillistUI/Editor). TaskEditorModel holds a draft in memory and, on promotion, calls TaskStore.create(...) in LillistCore/Stores-chunk-2.

4. TaskStore serializes the write through viewContext.perform with rollback-on-error. The LillistTask entity (LillistCore/ManagedObjects) is inserted into the NSPersistentCloudKitContainer managed by LillistCore/Persistence. FractionalIndexing math from LillistCore/Ordering computes the new row's position.

5. NSPersistentCloudKitContainer mirrors the new record to the private iCloud.app.lillist CloudKit container. CloudKitEventBridge (LillistCore/Sync-chunk-1) emits a sync event; SyncStatusMonitor (LillistCore/Sync-chunk-2) advances its aggregate; CloudKitSyncStatusAdapter (LillistUI/Status) converts the SyncStatus snapshot to a SyncIndicator enum case that the sync badge in TasksScreen reflects.

6. NotificationScheduler.reconcile(taskID:) (LillistCore/Notifications) runs a desired-vs-pending diff and installs a UNNotification if a reminder spec was included in the new task.

7. LocalBackupCoordinator (LillistCore/Backup) observes NSManagedObjectContextDidSave and appends the new task to the live incremental backup package on disk. DiagnosticHistoryObserver (LillistCore/Diagnostics) records the Core Data insertion as a structured JSONL event.

<!-- atlas:index-facts -->
- Four layers: LillistCore -> LillistUI -> iOS/macOS apps; extensions + CLI reuse core
- No NSManagedObject escapes LillistCore; store APIs return value DTOs (TaskRecord etc.)
- TaskStore is the single async gateway for all LillistTask CRUD, reorder, and status
- Date math uses Calendar; RecurrenceExpander is canonical, never addingTimeInterval
- Smart filters: NSPredicateCompiler + SwiftEvaluator twin backends kept in parity
- CLIBridge handlers are the shared verb layer for both lillist CLI and Shortcuts intents
- All targets share App Group group.app.lillist; CLI/extensions gated by MigrationGate
- LillistUI screens are state-free presenters; app wrappers own @State and navigation
<!-- /atlas:index-facts -->
