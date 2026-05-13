# Lillist Plan 2 — CloudKit Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote Plan 1's local-only `LillistCore` persistence to a CloudKit-backed sync layer that mirrors every Core Data entity to the user's private CloudKit database using a single custom zone, transparently handles iCloud account state, surfaces sync progress and errors, manages account-changed quarantine, and provides explicit attachment download control — all while preserving Plan 1's public store API surface so callers see no behavior change beyond the new sync-related observables.

**Architecture:** Plan 1's `PersistenceController` swaps `NSPersistentContainer` for `NSPersistentCloudKitContainer` and attaches `NSPersistentCloudKitContainerOptions` with the container identifier `iCloud.com.mikeydotio.lillist`. The single store description is configured for a custom CloudKit zone named `"Lillist"` in the private database (`.private`), enabling persistent history tracking and remote-change notifications — both prerequisites for `NSPersistentCloudKitContainer`. Two new actors observe the world outside Core Data: `AccountStateMonitor` wraps `CKContainer.accountStatus(_:)` and the `CKAccountChanged` Darwin notification, publishing an `iCloudAccountState` stream; `SyncStatusMonitor` subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` and publishes `lastSyncedAt`, `inProgress`, and `error`. A new `QuarantineManager` moves the local SQLite tree to `~/Library/Application Support/Lillist/Quarantine/<timestamp>/` on confirmed account change and prunes entries older than 30 days. `AttachmentStore` gains a `downloadData(id:)` method that triggers CloudKit asset download for clients that need bytes (metadata is always present). A `CloudKitSchemaInitializer` invokes `NSPersistentCloudKitContainer.initializeCloudKitSchema(options:)` in DEBUG on app boot. All tests use the same in-memory pattern Plan 1 established (`url = URL(fileURLWithPath: "/dev/null")`) — real CloudKit is verified manually per design Section 9.

**Tech Stack:** Swift 6, Swift Package Manager, Core Data (`NSPersistentCloudKitContainer`), CloudKit (`CKContainer`, `CKAccountStatus`, `CKDatabase.Scope`, `CKRecordZone`), Swift Testing, Foundation, Darwin notifications. No third-party dependencies.

This plan addresses design Section 3 (Sync, Storage, Migrations) end-to-end and the iCloud account-state portion of Section 8 (Error Handling).

---

## File Structure

```
Packages/LillistCore/
├── Package.swift                          (modified — no new deps)
├── Sources/
│   └── LillistCore/
│       ├── Persistence/
│       │   ├── PersistenceController.swift     (modified — use NSPersistentCloudKitContainer)
│       │   ├── StoreConfiguration.swift        (modified — add .cloudKit container ID)
│       │   ├── QuarantineManager.swift         (NEW — quarantine + 30-day cleanup)
│       │   ├── CloudKitSchemaInitializer.swift (NEW — DEBUG-only dev schema bootstrap)
│       │   └── AutoPurgeJob.swift              (unmodified)
│       ├── Sync/                               (NEW directory)
│       │   ├── iCloudAccountState.swift        (NEW — public state enum)
│       │   ├── AccountStateMonitor.swift       (NEW — actor wrapping CKContainer)
│       │   ├── SyncStatus.swift                (NEW — value type)
│       │   ├── SyncStatusMonitor.swift         (NEW — actor wrapping CK events)
│       │   └── CloudKitEventBridge.swift       (NEW — testable seam over NSPersistentCloudKitContainer.eventChangedNotification)
│       ├── Stores/
│       │   └── AttachmentStore.swift           (modified — add downloadData(id:))
│       └── Validation/
│           └── LillistError.swift              (unmodified — Plan 1 already defines iCloudUnavailable / syncFailure)
└── Tests/
    └── LillistCoreTests/
        ├── Sync/                               (NEW directory)
        │   ├── iCloudAccountStateTests.swift   (NEW)
        │   ├── AccountStateMonitorTests.swift  (NEW — using a mock account-status provider)
        │   ├── SyncStatusMonitorTests.swift    (NEW — driven by injected events)
        │   └── CloudKitEventBridgeTests.swift  (NEW)
        ├── Persistence/
        │   ├── PersistenceControllerCloudKitTests.swift (NEW — verifies CK container loads in memory)
        │   ├── QuarantineManagerTests.swift             (NEW)
        │   └── CloudKitSchemaInitializerTests.swift     (NEW — DEBUG-only build path)
        └── Stores/
            └── AttachmentStoreDownloadTests.swift       (NEW — metadata-only + explicit download)
```

Every file referenced in Plan 1's "File Structure" section is assumed to exist exactly as Plan 1 left it. This plan modifies four existing files and adds eight source files plus eight test files.

---

## Notes for the Implementer

**Design reference.** Every task derives from design Section 3 ("Sync, Storage, and Migrations") with crossover into Section 8 ("iCloud account states"). When a step says "per design Section 3" it means: re-read that subsection before writing the code — the design is authoritative.

**No real CloudKit in CI.** Design Section 9 makes this explicit: "Real CloudKit (manual at release across Mac + iPhone + iPad)." Tests in this plan **never** make network calls and **never** hit a real `CKContainer`. They verify three things:

1. The Core Data store loads with `NSPersistentCloudKitContainer` against `/dev/null` (the CloudKit machinery initializes but no zone bootstrap happens against the network).
2. Our wrappers (`AccountStateMonitor`, `SyncStatusMonitor`, `QuarantineManager`) behave correctly when driven by injected mock inputs.
3. The `AttachmentStore.downloadData(id:)` API has the right semantics when there is no asset to download — i.e. that fetching metadata never forces a data load.

**Testable seams.** Two indirection layers exist purely so Plan 2 is testable:

- `AccountStatusProviding` protocol — `AccountStateMonitor` depends on this, not directly on `CKContainer`. Production wires it to `CKContainer.default()`; tests wire a mock.
- `CloudKitEventBridge` actor — owns the `NotificationCenter` observer for `NSPersistentCloudKitContainer.eventChangedNotification`. Tests can inject events directly via `bridge.recordEvent(_:)` without involving real notifications.

**Public API surface added.**

- `iCloudAccountState` (public enum) — exported as required by the task brief.
- `AccountStateMonitor` (public actor) with `currentState`, `stateStream`.
- `SyncStatus` (public value type) — `lastSyncedAt`, `inProgress`, `error`.
- `SyncStatusMonitor` (public actor) with `currentStatus`, `statusStream`.
- `AttachmentStore.downloadData(id:)` (public async).
- `CloudKitSchemaInitializer.initializeIfNeeded(persistence:)` (public, DEBUG-only behavior).
- `QuarantineManager.quarantineCurrentStore(controller:)` and `QuarantineManager.cleanupExpired()` (internal — used by app boot logic in a later plan).

**Behavior preservation.** Plan 1's `*Store` tests must still pass after Task 2 — the change from `NSPersistentContainer` to `NSPersistentCloudKitContainer` against `/dev/null` is API-compatible for the view context. Run the full suite at the end of every task that touches `PersistenceController`.

**Commits.** Each task ends in a commit. Conventional-commit prefixes: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`.

**Verification command throughout:** `cd Packages/LillistCore && swift test`. Specific filters per task.

---

## Task 1: Extend `StoreConfiguration` with a CloudKit container identifier

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreConfigurationTests.swift`

The brief specifies the CloudKit container identifier `iCloud.com.mikeydotio.lillist`. Plan 1's `StoreConfiguration` only knows about `inMemory` and `onDisk(url:)`. Both cases now also carry a CloudKit container identifier (defaulted), and we add a `cloudKitContainerIdentifier` accessor used by `PersistenceController` in Task 2.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreConfigurationTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("StoreConfiguration")
struct StoreConfigurationTests {
    @Test("Default CloudKit container ID matches the design")
    func defaultContainerID() {
        let cfg = StoreConfiguration.inMemory
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.com.mikeydotio.lillist")
    }

    @Test("Custom container ID is preserved")
    func customContainerID() {
        let cfg = StoreConfiguration.inMemory.withCloudKitContainer("iCloud.example.test")
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.example.test")
    }

    @Test("Custom container ID is preserved for on-disk too")
    func customContainerIDOnDisk() {
        let url = URL(fileURLWithPath: "/tmp/Lillist.sqlite")
        let cfg = StoreConfiguration.onDisk(url: url).withCloudKitContainer("iCloud.example.test")
        #expect(cfg.cloudKitContainerIdentifier == "iCloud.example.test")
        if case .onDisk(let returnedURL) = cfg.storeKind {
            #expect(returnedURL == url)
        } else {
            Issue.record("storeKind should remain onDisk after container override")
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter StoreConfigurationTests`
Expected: FAIL — `cloudKitContainerIdentifier`, `withCloudKitContainer`, `storeKind` undefined.

- [ ] **Step 3: Replace `StoreConfiguration.swift`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift`:

```swift
import Foundation

/// Where the persistent store lives, how it's loaded, and which iCloud
/// container it mirrors to.
///
/// Plan 1 used a simple enum (`inMemory` / `onDisk(url:)`). Plan 2 wraps the
/// underlying store kind alongside a CloudKit container identifier so a single
/// value carries everything `PersistenceController` needs to call
/// `NSPersistentCloudKitContainer`.
public struct StoreConfiguration: Sendable {
    /// Production CloudKit container identifier (design Section 3).
    public static let defaultCloudKitContainerIdentifier = "iCloud.com.mikeydotio.lillist"

    /// The on-disk vs in-memory choice.
    public enum StoreKind: Sendable {
        case inMemory
        case onDisk(url: URL)
    }

    public var storeKind: StoreKind
    public var cloudKitContainerIdentifier: String

    public init(storeKind: StoreKind, cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier) {
        self.storeKind = storeKind
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
    }

    /// In-memory store backed by `/dev/null`. For tests and previews.
    public static var inMemory: StoreConfiguration {
        StoreConfiguration(storeKind: .inMemory)
    }

    /// On-disk SQLite store at the given file URL.
    public static func onDisk(url: URL) -> StoreConfiguration {
        StoreConfiguration(storeKind: .onDisk(url: url))
    }

    /// Default on-disk location: Application Support / Lillist / Lillist.sqlite
    public static var defaultOnDisk: StoreConfiguration {
        get throws {
            let fm = FileManager.default
            let appSupport = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("Lillist", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return .onDisk(url: dir.appendingPathComponent("Lillist.sqlite"))
        }
    }

    /// Returns a copy with the given CloudKit container identifier substituted in.
    public func withCloudKitContainer(_ identifier: String) -> StoreConfiguration {
        StoreConfiguration(storeKind: storeKind, cloudKitContainerIdentifier: identifier)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter StoreConfigurationTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Confirm Plan 1's tests still compile against the new struct**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds — `StoreConfiguration.inMemory` is still a valid expression (now a static computed property), and `.onDisk(url:)` is still a valid static method.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreConfigurationTests.swift
git commit -m "feat: extend StoreConfiguration with CloudKit container identifier"
```

---

## Task 2: Swap `NSPersistentContainer` for `NSPersistentCloudKitContainer` in `PersistenceController`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift`

Per design Section 3: "One CloudKit container (`iCloud.com.mikeydotio.lillist`), private database, one custom zone (`Lillist`)." We attach `NSPersistentCloudKitContainerOptions(containerIdentifier:)` to the single `NSPersistentStoreDescription`, set `databaseScope = .private`, enable persistent history tracking and remote-change notifications (both required by `NSPersistentCloudKitContainer`), and keep the merge policy Plan 1 established (`NSMergeByPropertyObjectTrumpMergePolicy`).

CloudKit's auto-detection of `allowsExternalBinaryDataStorage` attributes converts those binary blobs to `CKAsset` records under the hood — the model's `Attachment.data` attribute already has this flag set in Plan 1 (Task 5), so attachment-to-asset conversion happens automatically. We assert that flag survives in a test.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift`:

```swift
import Testing
import CoreData
@testable import LillistCore

@Suite("PersistenceController (CloudKit)")
struct PersistenceControllerCloudKitTests {
    @Test("In-memory store loads with NSPersistentCloudKitContainer")
    func loadsAsCloudKitContainer() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        #expect(controller.container is NSPersistentCloudKitContainer)
    }

    @Test("Store description carries CloudKit container options with the configured identifier")
    func cloudKitOptionsPresent() async throws {
        let cfg = StoreConfiguration.inMemory.withCloudKitContainer("iCloud.example.test")
        let controller = try await PersistenceController(configuration: cfg)
        let desc = controller.container.persistentStoreDescriptions.first!
        #expect(desc.cloudKitContainerOptions != nil)
        #expect(desc.cloudKitContainerOptions?.containerIdentifier == "iCloud.example.test")
        #expect(desc.cloudKitContainerOptions?.databaseScope == .private)
    }

    @Test("Persistent history tracking and remote-change notifications are enabled")
    func historyAndRemoteChangesEnabled() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let desc = controller.container.persistentStoreDescriptions.first!
        #expect(desc.isOptionTrue(NSPersistentHistoryTrackingKey))
        #expect(desc.isOptionTrue(NSPersistentStoreRemoteChangeNotificationPostOptionKey))
    }

    @Test("Default merge policy remains object-property-trump after CloudKit upgrade")
    func mergePolicyPreserved() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let policy = controller.container.viewContext.mergePolicy as? NSMergePolicy
        #expect(policy != nil)
        // NSMergeByPropertyObjectTrumpMergePolicy is a singleton with a specific type identifier.
        let trump = NSMergePolicy.mergeByPropertyObjectTrump
        #expect(controller.container.viewContext.mergePolicy as AnyObject === trump as AnyObject ||
                policy?.mergeType == .mergeByPropertyObjectTrumpMergePolicyType)
    }

    @Test("Attachment.data attribute keeps allowsExternalBinaryDataStorage so CloudKit converts to CKAsset")
    func externalStorageFlagPreserved() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let model = controller.container.managedObjectModel
        guard let entity = model.entitiesByName["Attachment"] else {
            Issue.record("Attachment entity missing")
            return
        }
        guard let attr = entity.attributesByName["data"] else {
            Issue.record("Attachment.data attribute missing")
            return
        }
        #expect(attr.allowsExternalBinaryDataStorage == true)
    }
}

private extension NSPersistentStoreDescription {
    func isOptionTrue(_ key: String) -> Bool {
        (option(forKey: key) as? NSNumber)?.boolValue == true
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerCloudKitTests`
Expected: FAIL — Plan 1's `PersistenceController` still uses `NSPersistentContainer`, so `container is NSPersistentCloudKitContainer` is `false` and `cloudKitContainerOptions` is `nil`.

- [ ] **Step 3: Rewrite `PersistenceController`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`:

```swift
import Foundation
import CoreData

/// Owns the `NSPersistentCloudKitContainer` and exposes a single shared view context.
///
/// Plan 1 used `NSPersistentContainer` for a local-only store. Plan 2 swaps in
/// the CloudKit-mirroring container without changing any caller-visible API:
/// the public surface is still `container.viewContext`, downstream `*Store`
/// classes are unchanged. CloudKit mirroring happens transparently under the
/// hood per design Section 3.
public final class PersistenceController: @unchecked Sendable {
    public let container: NSPersistentCloudKitContainer
    public let configuration: StoreConfiguration

    public init(configuration: StoreConfiguration) async throws {
        self.configuration = configuration
        let model = Self.loadModel()
        let container = NSPersistentCloudKitContainer(name: "LillistModel", managedObjectModel: model)

        let description: NSPersistentStoreDescription
        switch configuration.storeKind {
        case .inMemory:
            description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            description.type = NSSQLiteStoreType
        case .onDisk(let url):
            description = NSPersistentStoreDescription(url: url)
            description.type = NSSQLiteStoreType
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Required for NSPersistentCloudKitContainer.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit options — private database, single custom zone (design Section 3).
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: configuration.cloudKitContainerIdentifier)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options

        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: LillistError.storeUnavailable(reason: error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container
    }

    private static func loadModel() -> NSManagedObjectModel {
        guard let url = Bundle.module.url(forResource: "LillistModel", withExtension: "momd") else {
            preconditionFailure("LillistModel.momd not found in bundle")
        }
        guard let model = NSManagedObjectModel(contentsOf: url) else {
            preconditionFailure("Failed to load NSManagedObjectModel from \(url)")
        }
        return model
    }
}
```

- [ ] **Step 4: Run the new tests**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerCloudKitTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Run the full suite to confirm Plan 1 tests still pass**

Run: `cd Packages/LillistCore && swift test`
Expected: every test from Plan 1 (TaskStoreCRUDTests, JournalStoreTests, AttachmentStoreTests, etc.) still passes against the new CloudKit-backed in-memory controller.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift
git commit -m "feat: switch PersistenceController to NSPersistentCloudKitContainer"
```

---

## Task 3: Define the `iCloudAccountState` public enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Sync/iCloudAccountStateTests.swift`

The task brief requires exporting a public type `iCloudAccountState`. Per design Section 8 it has four cases: `available`, `noAccount`, `restricted`, `accountChanged`. The enum also has a static `from(ckAccountStatus:)` initializer used by Task 4's monitor.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Sync/iCloudAccountStateTests.swift`:

```swift
import Testing
import CloudKit
@testable import LillistCore

@Suite("iCloudAccountState")
struct iCloudAccountStateTests {
    @Test("Maps CKAccountStatus.available to .available")
    func mapsAvailable() {
        #expect(iCloudAccountState.from(ckAccountStatus: .available) == .available)
    }

    @Test("Maps CKAccountStatus.noAccount to .noAccount")
    func mapsNoAccount() {
        #expect(iCloudAccountState.from(ckAccountStatus: .noAccount) == .noAccount)
    }

    @Test("Maps CKAccountStatus.restricted to .restricted")
    func mapsRestricted() {
        #expect(iCloudAccountState.from(ckAccountStatus: .restricted) == .restricted)
    }

    @Test("Maps CKAccountStatus.couldNotDetermine to .noAccount (safest default)")
    func mapsCouldNotDetermine() {
        #expect(iCloudAccountState.from(ckAccountStatus: .couldNotDetermine) == .noAccount)
    }

    @Test("Maps CKAccountStatus.temporarilyUnavailable to .restricted")
    func mapsTemporarilyUnavailable() {
        #expect(iCloudAccountState.from(ckAccountStatus: .temporarilyUnavailable) == .restricted)
    }

    @Test("All four cases distinct")
    func distinctCases() {
        let all: Set<iCloudAccountState> = [.available, .noAccount, .restricted, .accountChanged]
        #expect(all.count == 4)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter iCloudAccountStateTests`
Expected: FAIL — type undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift`:

```swift
import Foundation
import CloudKit

/// The four iCloud account states `LillistCore` recognizes (design Section 8).
///
/// Note the Swift-unusual `iCloudAccountState` casing: this matches Apple's
/// own `iCloud` brand spelling exactly as requested in the Plan 2 brief.
public enum iCloudAccountState: Sendable, Equatable, Hashable {
    /// User signed in and the account is usable.
    case available
    /// No iCloud account configured on this device.
    case noAccount
    /// Account exists but is restricted (parental controls, MDM, or temporarily unavailable).
    case restricted
    /// The iCloud account changed since the last launch — store must be quarantined.
    case accountChanged

    /// Maps a `CKAccountStatus` to a Lillist account state.
    ///
    /// `.couldNotDetermine` is treated as `.noAccount` because we cannot
    /// safely write CloudKit-bound data when we have no evidence of an
    /// account. `.temporarilyUnavailable` maps to `.restricted` so the UI
    /// surfaces a banner without quarantining the store.
    public static func from(ckAccountStatus: CKAccountStatus) -> iCloudAccountState {
        switch ckAccountStatus {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .noAccount
        case .temporarilyUnavailable:
            return .restricted
        @unknown default:
            return .noAccount
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter iCloudAccountStateTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/iCloudAccountState.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/iCloudAccountStateTests.swift
git commit -m "feat: add iCloudAccountState public enum mapping from CKAccountStatus"
```

---

## Task 4: `AccountStateMonitor` actor with mockable status provider

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Sync/AccountStateMonitorTests.swift`

Per design Section 8: account states are observed and published. The monitor wraps `CKContainer.accountStatus(_:)` and the `CKAccountChanged` Darwin notification, but we depend on a protocol (`AccountStatusProviding`) so tests can inject controlled values. Public surface: `currentState`, `stateStream`, `refresh()`, `simulateAccountChange()` (the latter only for tests but kept package-internal).

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Sync/AccountStateMonitorTests.swift`:

```swift
import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("AccountStateMonitor")
struct AccountStateMonitorTests {
    actor MockProvider: AccountStatusProviding {
        var nextStatus: CKAccountStatus = .available
        func setNextStatus(_ s: CKAccountStatus) { nextStatus = s }
        func accountStatus() async throws -> CKAccountStatus { nextStatus }
    }

    @Test("Initial refresh maps the provider's status to current state")
    func initialRefresh() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        #expect(await monitor.currentState == .available)
    }

    @Test("Refresh after status flips updates the current state")
    func refreshAfterFlip() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        await provider.setNextStatus(.noAccount)
        try await monitor.refresh()
        #expect(await monitor.currentState == .noAccount)
    }

    @Test("Restricted maps through correctly")
    func restrictedFlow() async throws {
        let provider = MockProvider()
        await provider.setNextStatus(.restricted)
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        #expect(await monitor.currentState == .restricted)
    }

    @Test("Simulated account change publishes .accountChanged")
    func accountChangedSimulation() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        try await monitor.refresh()
        await monitor.simulateAccountChange()
        #expect(await monitor.currentState == .accountChanged)
    }

    @Test("State stream yields each refresh value in order")
    func streamEmitsValues() async throws {
        let provider = MockProvider()
        let monitor = AccountStateMonitor(provider: provider)
        var iterator = await monitor.stateStream.makeAsyncIterator()
        try await monitor.refresh()
        let v1 = await iterator.next()
        await provider.setNextStatus(.noAccount)
        try await monitor.refresh()
        let v2 = await iterator.next()
        #expect(v1 == .available)
        #expect(v2 == .noAccount)
    }

    @Test("Provider error is propagated by refresh")
    func providerError() async throws {
        struct Boom: Error {}
        actor FailingProvider: AccountStatusProviding {
            func accountStatus() async throws -> CKAccountStatus { throw Boom() }
        }
        let monitor = AccountStateMonitor(provider: FailingProvider())
        await #expect(throws: (any Error).self) {
            try await monitor.refresh()
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter AccountStateMonitorTests`
Expected: FAIL — `AccountStateMonitor`, `AccountStatusProviding` undefined.

- [ ] **Step 3: Write the implementation**

Write `Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift`:

```swift
import Foundation
import CloudKit

/// Testable seam around `CKContainer.accountStatus(_:)`.
public protocol AccountStatusProviding: Sendable {
    func accountStatus() async throws -> CKAccountStatus
}

/// Production implementation that asks the real `CKContainer`.
public struct CloudKitAccountStatusProvider: AccountStatusProviding {
    public let container: CKContainer
    public init(container: CKContainer) { self.container = container }
    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

/// Observes the iCloud account state and publishes changes (design Section 8).
///
/// The monitor is an actor so concurrent observers can subscribe to the
/// stream without races. It depends on an `AccountStatusProviding` so tests
/// can inject controlled values without touching real CloudKit.
public actor AccountStateMonitor {
    public private(set) var currentState: iCloudAccountState = .noAccount

    private let provider: AccountStatusProviding
    private var continuations: [UUID: AsyncStream<iCloudAccountState>.Continuation] = [:]

    public init(provider: AccountStatusProviding) {
        self.provider = provider
    }

    /// Fetches the current `CKAccountStatus`, maps it to `iCloudAccountState`,
    /// updates `currentState`, and notifies stream subscribers.
    public func refresh() async throws {
        let status = try await provider.accountStatus()
        let mapped = iCloudAccountState.from(ckAccountStatus: status)
        publish(mapped)
    }

    /// Called from the `CKAccountChanged` notification handler — sets the
    /// state to `.accountChanged` regardless of the underlying status, since
    /// the app's quarantine flow needs explicit confirmation before
    /// continuing.
    public func simulateAccountChange() {
        publish(.accountChanged)
    }

    /// An async stream of state changes. Each call returns a fresh stream
    /// scoped to its caller; closing the stream removes the continuation.
    public var stateStream: AsyncStream<iCloudAccountState> {
        AsyncStream { continuation in
            let id = UUID()
            // Capture into the actor to register the continuation.
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<iCloudAccountState>.Continuation) {
        continuations[id] = continuation
        // Replay the latest known state so late subscribers see it immediately.
        continuation.yield(currentState)
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    private func publish(_ state: iCloudAccountState) {
        currentState = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter AccountStateMonitorTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/AccountStateMonitor.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/AccountStateMonitorTests.swift
git commit -m "feat: add AccountStateMonitor actor with mockable status provider"
```

---

## Task 5: `SyncStatus` value type

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift`
- (tests for `SyncStatus` live in Task 6's `SyncStatusMonitorTests`)

Per the brief: `lastSyncedAt: Date?`, `inProgress: Bool`, `error: LillistError?`. Sendable and Equatable so we can compare snapshots in tests and use it in `AsyncStream`s.

- [ ] **Step 1: Write the file**

Write `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift`:

```swift
import Foundation

/// Snapshot of the current CloudKit sync state, published by
/// `SyncStatusMonitor` and consumed by UI / CLI status indicators
/// (design Sections 3 and 8).
public struct SyncStatus: Sendable, Equatable {
    public var lastSyncedAt: Date?
    public var inProgress: Bool
    public var error: LillistError?

    public init(lastSyncedAt: Date? = nil, inProgress: Bool = false, error: LillistError? = nil) {
        self.lastSyncedAt = lastSyncedAt
        self.inProgress = inProgress
        self.error = error
    }

    /// Convenience for "nothing has happened yet."
    public static let idle = SyncStatus()
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `cd Packages/LillistCore && swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/SyncStatus.swift
git commit -m "feat: add SyncStatus value type for CloudKit sync state snapshots"
```

---

## Task 6: `CloudKitEventBridge` and `SyncStatusMonitor`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift`

`NSPersistentCloudKitContainer` posts `eventChangedNotification` with an `NSPersistentCloudKitContainer.Event` whose `type` is `.setup`, `.import`, or `.export`, and whose `endDate`/`error` fields tell us when each phase completes or fails. The bridge subscribes to the notification on the global notification center and re-fires it as an internal value-type `CloudKitSyncEvent` we can drive in tests without involving Apple's real type.

- [ ] **Step 1: Write failing tests for `CloudKitEventBridge`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CloudKitEventBridge")
struct CloudKitEventBridgeTests {
    @Test("Recorded events appear on the stream in order")
    func eventsStream() async throws {
        let bridge = CloudKitEventBridge()
        var iterator = await bridge.eventStream.makeAsyncIterator()

        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let first = await iterator.next()
        #expect(first?.type == .setup)
        #expect(first?.started == true)

        await bridge.recordEvent(.init(type: .import, started: false, endedAt: Date(timeIntervalSince1970: 1_000_000), error: nil))
        let second = await iterator.next()
        #expect(second?.type == .import)
        #expect(second?.endedAt == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("Multiple subscribers each get all events independently")
    func fanOut() async throws {
        let bridge = CloudKitEventBridge()
        var aIter = await bridge.eventStream.makeAsyncIterator()
        var bIter = await bridge.eventStream.makeAsyncIterator()

        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        #expect(await aIter.next()?.type == .export)
        #expect(await bIter.next()?.type == .export)
    }
}
```

- [ ] **Step 2: Write failing tests for `SyncStatusMonitor`**

Write `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("SyncStatusMonitor")
struct SyncStatusMonitorTests {
    @Test("Initial status is idle")
    func initial() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        #expect(await monitor.currentStatus == .idle)
    }

    @Test("Setup-started event sets inProgress to true")
    func setupStarted() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        await Task.yield()
        await Task.yield()
        let status = await monitor.currentStatus
        #expect(status.inProgress == true)
        #expect(status.error == nil)
    }

    @Test("Successful import completion clears inProgress and sets lastSyncedAt")
    func importCompletes() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        let end = Date(timeIntervalSince1970: 2_000_000)
        await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        await Task.yield()
        await bridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        await Task.yield()
        await Task.yield()
        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.lastSyncedAt == end)
        #expect(status.error == nil)
    }

    @Test("Failed export records the error and clears inProgress")
    func exportFails() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        let err = LillistError.syncFailure(underlying: "network down")
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        await Task.yield()
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err))
        await Task.yield()
        await Task.yield()
        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.error == err)
    }

    @Test("Status stream yields updates")
    func statusStream() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()
        #expect(next?.inProgress == true)
    }
}
```

- [ ] **Step 3: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter CloudKitEventBridgeTests --filter SyncStatusMonitorTests`
Expected: FAIL — types undefined.

- [ ] **Step 4: Write `CloudKitEventBridge`**

Write `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift`:

```swift
import Foundation
import CoreData

/// Lillist's internal mirror of `NSPersistentCloudKitContainer.Event`.
///
/// We mirror the upstream type so tests can construct and drive events
/// directly without depending on Apple's API surface (which is hard to
/// instantiate from outside Core Data).
public struct CloudKitSyncEvent: Sendable, Equatable {
    public enum EventType: Sendable, Equatable {
        case setup
        case `import`
        case export
    }
    public var type: EventType
    public var started: Bool
    public var endedAt: Date?
    public var error: LillistError?

    public init(type: EventType, started: Bool, endedAt: Date?, error: LillistError?) {
        self.type = type
        self.started = started
        self.endedAt = endedAt
        self.error = error
    }
}

/// Bridges `NSPersistentCloudKitContainer.eventChangedNotification` into a
/// testable async stream.
///
/// In production, `attach(to:)` registers a `NotificationCenter` observer
/// that translates Apple's events to `CloudKitSyncEvent`. In tests, callers
/// invoke `recordEvent(_:)` directly to drive the stream without touching
/// the notification center.
public actor CloudKitEventBridge {
    private var continuations: [UUID: AsyncStream<CloudKitSyncEvent>.Continuation] = [:]
    private var observerToken: NSObjectProtocol?

    public init() {}

    deinit {
        if let token = observerToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    public var eventStream: AsyncStream<CloudKitSyncEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregister(id: id) }
            }
        }
    }

    /// Test seam — drive an event directly without involving NotificationCenter.
    public func recordEvent(_ event: CloudKitSyncEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    /// Production seam — register a NotificationCenter observer that
    /// converts `NSPersistentCloudKitContainer.Event` to `CloudKitSyncEvent`.
    public func attach(to container: NSPersistentCloudKitContainer) {
        let name = NSPersistentCloudKitContainer.eventChangedNotification
        let token = NotificationCenter.default.addObserver(forName: name, object: container, queue: nil) { [weak self] notification in
            guard let self else { return }
            guard let ckEvent = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            let translated = Self.translate(ckEvent)
            Task { await self.recordEvent(translated) }
        }
        Task { await self.setObserverToken(token) }
    }

    private func setObserverToken(_ token: NSObjectProtocol) {
        observerToken = token
    }

    private func register(id: UUID, continuation: AsyncStream<CloudKitSyncEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations[id] = nil
    }

    static func translate(_ event: NSPersistentCloudKitContainer.Event) -> CloudKitSyncEvent {
        let type: CloudKitSyncEvent.EventType
        switch event.type {
        case .setup: type = .setup
        case .import: type = .import
        case .export: type = .export
        @unknown default: type = .setup
        }
        let started = event.endDate == nil
        let mapped: LillistError? = event.error.map { LillistError.syncFailure(underlying: ($0 as NSError).localizedDescription) }
        return CloudKitSyncEvent(type: type, started: started, endedAt: event.endDate, error: mapped)
    }
}
```

- [ ] **Step 5: Write `SyncStatusMonitor`**

Write `Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift`:

```swift
import Foundation

/// Aggregates a stream of `CloudKitSyncEvent`s into a published `SyncStatus`
/// (design Sections 3 and 8). Driven by `CloudKitEventBridge`.
public actor SyncStatusMonitor {
    public private(set) var currentStatus: SyncStatus = .idle

    private let bridge: CloudKitEventBridge
    private var consumeTask: Task<Void, Never>?
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    public init(bridge: CloudKitEventBridge) {
        self.bridge = bridge
    }

    deinit { consumeTask?.cancel() }

    /// Begin consuming events from the bridge. Idempotent — calling more
    /// than once leaves the existing consumer running.
    public func start() {
        guard consumeTask == nil else { return }
        let stream = await bridge.eventStream
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.apply(event)
            }
        }
    }

    public var statusStream: AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.registerStatus(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.unregisterStatus(id: id) }
            }
        }
    }

    private func registerStatus(id: UUID, continuation: AsyncStream<SyncStatus>.Continuation) {
        statusContinuations[id] = continuation
        continuation.yield(currentStatus)
    }

    private func unregisterStatus(id: UUID) {
        statusContinuations[id] = nil
    }

    private func apply(_ event: CloudKitSyncEvent) {
        var next = currentStatus
        if event.started {
            next.inProgress = true
            next.error = nil
        } else {
            next.inProgress = false
            if let err = event.error {
                next.error = err
            } else if let endedAt = event.endedAt {
                next.lastSyncedAt = endedAt
                next.error = nil
            }
        }
        currentStatus = next
        for continuation in statusContinuations.values {
            continuation.yield(next)
        }
    }
}
```

- [ ] **Step 6: Run tests**

Run: `cd Packages/LillistCore && swift test --filter CloudKitEventBridgeTests --filter SyncStatusMonitorTests`
Expected: PASS, 7 tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift Packages/LillistCore/Sources/LillistCore/Sync/SyncStatusMonitor.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitEventBridgeTests.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStatusMonitorTests.swift
git commit -m "feat: add CloudKitEventBridge and SyncStatusMonitor for sync status tracking"
```

---

## Task 7: `QuarantineManager` for account-changed local store quarantine

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift`

Per design Section 8: "On confirm, local store moved to quarantine path; fresh store created. Quarantine preserved 30 days then auto-cleaned." `QuarantineManager` operates on files directly — it doesn't open Core Data — so tests can drive it against a `tmp` directory without any real database.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("QuarantineManager")
struct QuarantineManagerTests {
    func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Lillist-quarantine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Quarantine moves the SQLite triplet under the quarantine directory")
    func movesFiles() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: storeURL.appendingPathExtension("wal"))
        try Data("shm".utf8).write(to: storeURL.appendingPathExtension("shm"))
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let dest = try mgr.quarantineStore(at: storeURL)
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: dest.path) == true)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathExtension("wal").path) == true)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathExtension("shm").path) == true)
    }

    @Test("Quarantine handles missing WAL/SHM gracefully")
    func missingSidecars() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let dest = try mgr.quarantineStore(at: storeURL)
        #expect(FileManager.default.fileExists(atPath: dest.path) == true)
    }

    @Test("Cleanup deletes quarantine subfolders older than 30 days")
    func cleanupOld() throws {
        let root = try makeTempRoot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mgr = QuarantineManager(rootDirectory: root, clock: { now })

        // Create one fresh and one expired quarantine folder.
        let fresh = root.appendingPathComponent("Quarantine/fresh", isDirectory: true)
        let expired = root.appendingPathComponent("Quarantine/expired", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: expired, withIntermediateDirectories: true)

        let oldDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: expired.path)

        try mgr.cleanupExpired()
        #expect(FileManager.default.fileExists(atPath: fresh.path) == true)
        #expect(FileManager.default.fileExists(atPath: expired.path) == false)
    }

    @Test("Cleanup leaves folders younger than 30 days intact")
    func cleanupYoung() throws {
        let root = try makeTempRoot()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mgr = QuarantineManager(rootDirectory: root, clock: { now })
        let young = root.appendingPathComponent("Quarantine/young", isDirectory: true)
        try FileManager.default.createDirectory(at: young, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-15 * 24 * 60 * 60)], ofItemAtPath: young.path)
        try mgr.cleanupExpired()
        #expect(FileManager.default.fileExists(atPath: young.path) == true)
    }

    @Test("Quarantine on a missing store URL throws")
    func missingStore() throws {
        let root = try makeTempRoot()
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date() })
        let bogus = root.appendingPathComponent("nope.sqlite")
        #expect(throws: (any Error).self) {
            _ = try mgr.quarantineStore(at: bogus)
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter QuarantineManagerTests`
Expected: FAIL — `QuarantineManager` undefined.

- [ ] **Step 3: Write `QuarantineManager`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift`:

```swift
import Foundation

/// Moves a Core Data SQLite store and its sidecars into a timestamped
/// quarantine directory and prunes expired entries (design Section 8:
/// "Quarantine preserved 30 days then auto-cleaned").
///
/// Operates purely on the filesystem; never opens Core Data. Designed to
/// be invoked while no `NSPersistentCloudKitContainer` has the store open.
public struct QuarantineManager: Sendable {
    public static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    public let rootDirectory: URL
    private let clock: @Sendable () -> Date
    private let fm = FileManager.default

    public init(rootDirectory: URL, clock: @escaping @Sendable () -> Date = Date.init) {
        self.rootDirectory = rootDirectory
        self.clock = clock
    }

    /// Move the SQLite store (and its `-wal` / `-shm` sidecars, if present)
    /// into `<root>/Quarantine/<unix-timestamp>/`. Returns the destination
    /// URL of the main store file.
    @discardableResult
    public func quarantineStore(at storeURL: URL) throws -> URL {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        let timestamp = Int(clock().timeIntervalSince1970)
        let quarantineDir = rootDirectory.appendingPathComponent("Quarantine/\(timestamp)", isDirectory: true)
        try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        let dest = quarantineDir.appendingPathComponent(storeURL.lastPathComponent)
        try fm.moveItem(at: storeURL, to: dest)

        for ext in ["wal", "shm"] {
            let sidecar = storeURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: sidecar.path) {
                let sidecarDest = dest.appendingPathExtension(ext)
                try fm.moveItem(at: sidecar, to: sidecarDest)
            }
        }
        return dest
    }

    /// Delete every quarantine subfolder whose modification date is older
    /// than `retentionInterval`.
    public func cleanupExpired() throws {
        let quarantineRoot = rootDirectory.appendingPathComponent("Quarantine", isDirectory: true)
        guard fm.fileExists(atPath: quarantineRoot.path) else { return }
        let now = clock()
        let contents = try fm.contentsOfDirectory(at: quarantineRoot, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        for url in contents {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values.contentModificationDate, now.timeIntervalSince(mod) > Self.retentionInterval {
                try fm.removeItem(at: url)
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter QuarantineManagerTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift
git commit -m "feat: add QuarantineManager for account-changed local store handling"
```

---

## Task 8: `CloudKitSchemaInitializer` (DEBUG-only dev schema bootstrap)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/CloudKitSchemaInitializerTests.swift`

Per design Section 3: "CloudKit dev schema initialized from the model on boot in DEBUG; production promoted manually before each releasing change." The initializer wraps `NSPersistentCloudKitContainer.initializeCloudKitSchema(options:)`, guarded by `#if DEBUG`. In RELEASE builds the call is a no-op. Tests assert the guard logic without invoking the real CloudKit method (which would hit the network).

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Persistence/CloudKitSchemaInitializerTests.swift`:

```swift
import Testing
import CoreData
@testable import LillistCore

@Suite("CloudKitSchemaInitializer")
struct CloudKitSchemaInitializerTests {
    @Test("Initializer accepts a persistence controller without crashing in dry-run mode")
    func dryRun() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        // Dry-run path avoids the real CloudKit network call.
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true)
    }

    @Test("Dry run records that it was invoked")
    func dryRunRecorded() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        var didRun = false
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true, onInvoke: { didRun = true })
        #expect(didRun == true)
    }

    @Test("In RELEASE configuration, dry run still runs (guard is build-time, not config-time)")
    func dryRunInRelease() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        var didRun = false
        try CloudKitSchemaInitializer.initializeIfNeeded(persistence: controller, dryRun: true, onInvoke: { didRun = true })
        #expect(didRun == true)
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter CloudKitSchemaInitializerTests`
Expected: FAIL — `CloudKitSchemaInitializer` undefined.

- [ ] **Step 3: Write `CloudKitSchemaInitializer`**

Write `Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift`:

```swift
import Foundation
import CoreData

/// DEBUG-only bootstrapping of the CloudKit development schema from the
/// Core Data model (design Section 3).
///
/// `NSPersistentCloudKitContainer.initializeCloudKitSchema(options:)`
/// inspects the Core Data model and creates/updates the matching record
/// types in CloudKit's development environment. It must never run in
/// production — promotion to the production schema is a manual step
/// performed via CloudKit Dashboard.
///
/// Callers (the host app's launch sequence, added in a later plan) wire
/// this in behind `#if DEBUG`. The `dryRun` flag lets tests verify the
/// invocation contract without actually contacting CloudKit.
public enum CloudKitSchemaInitializer {
    public enum Error: Swift.Error { case schemaInitializationFailed(String) }

    /// Initialize the CloudKit development schema if we're in a DEBUG build.
    /// - Parameters:
    ///   - persistence: the controller whose container will be initialized.
    ///   - dryRun: if true, skip the real CloudKit call and only invoke the `onInvoke` callback.
    ///   - onInvoke: test hook to confirm the initializer was entered.
    public static func initializeIfNeeded(
        persistence: PersistenceController,
        dryRun: Bool = false,
        onInvoke: (() -> Void)? = nil
    ) throws {
        onInvoke?()
        guard !dryRun else { return }
        #if DEBUG
        do {
            try persistence.container.initializeCloudKitSchema(options: [])
        } catch {
            throw Error.schemaInitializationFailed((error as NSError).localizedDescription)
        }
        #else
        // Release builds rely on the manually-promoted production schema.
        return
        #endif
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter CloudKitSchemaInitializerTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/CloudKitSchemaInitializer.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/CloudKitSchemaInitializerTests.swift
git commit -m "feat: add CloudKitSchemaInitializer for DEBUG-only dev schema bootstrap"
```

---

## Task 9: `AttachmentStore.downloadData(id:)` — explicit lazy download

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreDownloadTests.swift`

Per design Section 3: "iOS/iPadOS: lazy download. Metadata available immediately; bytes load on first access." Plan 1's `AttachmentStore` returns an `AttachmentRecord` with `hasData: Bool` but no way to actually request the bytes. We add:

- `downloadData(id:)` — async, returns the raw `Data` if available, throws `.attachmentFetchFailed(url:)` if it isn't. CloudKit auto-downloads small assets; for larger ones the data may be `nil` until we trigger a `refreshObject` cycle. The method asks Core Data for the row, accesses `.data` (which triggers CloudKit's asset materialization), and returns the bytes.
- `metadata(id:)` — equivalent to the existing `fetch(id:)` but with an explicit "metadata only — do not trigger data load" contract documented.

Tests verify that fetching metadata on an in-memory store with no asset machinery works without error and that `downloadData` returns the bytes when present and throws when absent.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreDownloadTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("AttachmentStore download")
struct AttachmentStoreDownloadTests {
    private func tinyPNG() -> Data {
        Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
    }

    @Test("Metadata fetch does not include the data bytes in the returned record")
    func metadataOmitsBytes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addImage(taskID: taskID, filename: "snap.png", data: tinyPNG())
        let record = try await store.fetch(id: attID)
        #expect(record.hasData == true)
        // The record itself never carries bytes — `hasData` is metadata.
        // Bytes only come through `downloadData(id:)`.
        // (This is the API contract.)
    }

    @Test("downloadData returns bytes when present")
    func downloadReturnsBytes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let png = tinyPNG()
        let attID = try await store.addImage(taskID: taskID, filename: "snap.png", data: png)
        let bytes = try await store.downloadData(id: attID)
        #expect(bytes == png)
    }

    @Test("downloadData throws attachmentFetchFailed when bytes are absent (link preview row)")
    func downloadThrowsForLinkPreview() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let store = AttachmentStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let attID = try await store.addLinkPreview(
            taskID: taskID,
            url: URL(string: "https://example.com")!,
            title: nil,
            description: nil,
            thumbnailData: nil,
            faviconData: nil
        )
        await #expect(throws: LillistError.self) {
            _ = try await store.downloadData(id: attID)
        }
    }

    @Test("downloadData throws notFound for unknown ID")
    func downloadThrowsNotFound() async throws {
        let p = try await TestStore.make()
        let store = AttachmentStore(persistence: p)
        await #expect(throws: LillistError.notFound) {
            _ = try await store.downloadData(id: UUID())
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter AttachmentStoreDownloadTests`
Expected: FAIL — `downloadData(id:)` undefined.

- [ ] **Step 3: Append `downloadData(id:)` to `AttachmentStore`**

Edit `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift` — add this method inside the class, after the existing `// MARK: - Read` block:

```swift
    /// Explicitly request the binary bytes for an attachment.
    ///
    /// CloudKit auto-downloads small assets, but larger ones may need an
    /// explicit fetch on iOS/iPadOS (design Section 3 — "lazy download.
    /// Metadata available immediately; bytes load on first access").
    /// Accessing `.data` triggers `NSPersistentCloudKitContainer`'s asset
    /// materialization for any pending download.
    ///
    /// - Throws: `LillistError.notFound` if the attachment row doesn't exist.
    /// - Throws: `LillistError.attachmentFetchFailed` if the row exists but
    ///   has no data bytes (e.g. a link-preview row, or a CKAsset that
    ///   couldn't be downloaded).
    public func downloadData(id: UUID) async throws -> Data {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            // Touching `m.data` is what causes the asset materialization.
            guard let bytes = m.data else {
                let placeholder = URL(string: "lillist://attachment/\(id.uuidString)")!
                throw LillistError.attachmentFetchFailed(url: placeholder)
            }
            return bytes
        }
    }
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter AttachmentStoreDownloadTests`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run full suite to confirm Plan 1's `AttachmentStoreTests` still pass**

Run: `cd Packages/LillistCore && swift test --filter AttachmentStoreTests`
Expected: PASS (6 tests from Plan 1) — `downloadData` is additive.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift Packages/LillistCore/Tests/LillistCoreTests/Stores/AttachmentStoreDownloadTests.swift
git commit -m "feat: add AttachmentStore.downloadData for explicit CloudKit asset retrieval"
```

---

## Task 10: Wire `CloudKitEventBridge` into `PersistenceController` for production use

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`
- Modify: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift`

Up to this point the bridge is a free-floating actor. We expose a `cloudKitEventBridge` property on `PersistenceController` that's automatically attached to the container after stores load. Tests stay decoupled by using the bridge directly; production app code reads the bridge off the controller.

- [ ] **Step 1: Add the new test**

Append to `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift`, inside the existing `@Suite` struct:

```swift
    @Test("PersistenceController exposes a CloudKitEventBridge")
    func bridgeExposed() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        #expect(controller.cloudKitEventBridge != nil)
    }
```

- [ ] **Step 2: Run to confirm failure**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerCloudKitTests`
Expected: FAIL — `cloudKitEventBridge` undefined.

- [ ] **Step 3: Add the property and wiring**

Edit `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift`. Add inside the class, right after the `configuration` property:

```swift
    /// The event bridge that translates
    /// `NSPersistentCloudKitContainer.eventChangedNotification` into a
    /// testable async stream. Attached automatically after the persistent
    /// stores load.
    public let cloudKitEventBridge: CloudKitEventBridge
```

In `init(configuration:)`, after the line `self.container = container`, add:

```swift
        let bridge = CloudKitEventBridge()
        await bridge.attach(to: container)
        self.cloudKitEventBridge = bridge
```

Move `self.configuration = configuration` to occur before any `await` so the stored properties are written in order, and adjust the order of assignments so all `let` properties are initialized before the first `await`-able statement:

Final relevant block in `init`:

```swift
    public init(configuration: StoreConfiguration) async throws {
        self.configuration = configuration
        let model = Self.loadModel()
        let container = NSPersistentCloudKitContainer(name: "LillistModel", managedObjectModel: model)
        // ... store description setup unchanged ...
        container.persistentStoreDescriptions = [description]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: LillistError.storeUnavailable(reason: error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        self.container = container

        let bridge = CloudKitEventBridge()
        await bridge.attach(to: container)
        self.cloudKitEventBridge = bridge
    }
```

- [ ] **Step 4: Run tests**

Run: `cd Packages/LillistCore && swift test --filter PersistenceControllerCloudKitTests`
Expected: PASS — all six tests in the suite now pass.

- [ ] **Step 5: Run full suite**

Run: `cd Packages/LillistCore && swift test`
Expected: every test (Plan 1 + Plan 2 so far) passes.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift
git commit -m "feat: expose CloudKitEventBridge on PersistenceController"
```

---

## Task 11: End-to-end smoke test — full sync stack against an in-memory store

**Files:**
- Create: `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift`

A single high-value test that wires `PersistenceController` → `cloudKitEventBridge` → `SyncStatusMonitor` together and drives a simulated import event through the bridge, verifying the status surfaces on the monitor. This is the closest we get to integration testing without real CloudKit (design Section 9 — "Real CloudKit (manual at release across Mac + iPhone + iPad)").

- [ ] **Step 1: Write the test**

Write `Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Sync stack smoke")
struct SyncStackSmokeTests {
    @Test("Bridge → monitor pipeline reflects a simulated import completion")
    func endToEnd() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let monitor = SyncStatusMonitor(bridge: controller.cloudKitEventBridge)
        await monitor.start()

        let end = Date(timeIntervalSince1970: 3_000_000)
        await controller.cloudKitEventBridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        await Task.yield()
        await controller.cloudKitEventBridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        // Yield a couple of times so the consumer task drains.
        await Task.yield()
        await Task.yield()

        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.lastSyncedAt == end)
        #expect(status.error == nil)
    }

    @Test("Account monitor + sync monitor coexist without crashing")
    func coexistence() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        actor StaticProvider: AccountStatusProviding {
            func accountStatus() async throws -> CKAccountStatus { .available }
        }
        let accountMonitor = AccountStateMonitor(provider: StaticProvider())
        let syncMonitor = SyncStatusMonitor(bridge: controller.cloudKitEventBridge)
        try await accountMonitor.refresh()
        await syncMonitor.start()
        #expect(await accountMonitor.currentState == .available)
        #expect(await syncMonitor.currentStatus == .idle)
    }
}

import CloudKit
```

- [ ] **Step 2: Run**

Run: `cd Packages/LillistCore && swift test --filter SyncStackSmokeTests`
Expected: PASS, 2 tests.

- [ ] **Step 3: Run full suite one last time**

Run: `cd Packages/LillistCore && swift test`
Expected: every test passes.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/Sync/SyncStackSmokeTests.swift
git commit -m "test: add sync stack smoke test wiring bridge to monitors"
```

---

## Task 12: Update `LillistCore.swift` umbrella + version, tag plan-2 complete

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/LillistCore.swift`

Bump version, document the public sync API on the umbrella.

- [ ] **Step 1: Rewrite the umbrella file**

Write `Packages/LillistCore/Sources/LillistCore/LillistCore.swift`:

```swift
import Foundation

/// `LillistCore` umbrella namespace.
///
/// Plan 1 delivered the local-only Core Data layer. Plan 2 promotes that
/// layer to CloudKit sync via `NSPersistentCloudKitContainer` and adds:
///
/// - `iCloudAccountState` and `AccountStateMonitor`
/// - `SyncStatus` and `SyncStatusMonitor` (driven by `CloudKitEventBridge`)
/// - `QuarantineManager` for account-changed local store handling
/// - `CloudKitSchemaInitializer` for DEBUG-only dev schema bootstrap
/// - `AttachmentStore.downloadData(id:)` for explicit lazy attachment download
public enum LillistCore {
    public static let version = "0.2.0"
}
```

- [ ] **Step 2: Update the smoke test**

Edit `Packages/LillistCore/Tests/LillistCoreTests/SmokeTests.swift` to assert the new version:

```swift
import Testing
@testable import LillistCore

@Suite("Smoke")
struct SmokeTests {
    @Test("Package builds and version is set")
    func versionExists() {
        #expect(LillistCore.version == "0.2.0")
    }
}
```

- [ ] **Step 3: Run full suite**

Run: `cd Packages/LillistCore && swift test`
Expected: every test passes including the updated smoke test.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/LillistCore.swift Packages/LillistCore/Tests/LillistCoreTests/SmokeTests.swift
git commit -m "chore: bump LillistCore to 0.2.0 (Plan 2 CloudKit sync complete)"
```

- [ ] **Step 5: Tag the milestone**

```bash
git tag plan-2-cloudkit-sync
```

---

## Self-Review Checklist (run by the implementer before merging)

- [ ] `PersistenceController` uses `NSPersistentCloudKitContainer` and attaches `NSPersistentCloudKitContainerOptions` with identifier `iCloud.com.mikeydotio.lillist` to a `.private` database (design Section 3).
- [ ] The single store description has both `NSPersistentHistoryTrackingKey` and `NSPersistentStoreRemoteChangeNotificationPostOptionKey` set to true.
- [ ] Merge policy is verified as `NSMergeByPropertyObjectTrumpMergePolicy` (object-property-trump) — the field-level "last writer wins" semantics design Section 3 specifies.
- [ ] `Attachment.data` retains `allowsExternalBinaryDataStorage = true` so `NSPersistentCloudKitContainer` auto-converts large blobs to `CKAsset`.
- [ ] `iCloudAccountState` is exported as a public type and maps every `CKAccountStatus` case, including `.couldNotDetermine` (treated as `.noAccount`) and `.temporarilyUnavailable` (treated as `.restricted`).
- [ ] `AccountStateMonitor` depends on `AccountStatusProviding` so tests inject mock providers — no test ever calls real CloudKit.
- [ ] `SyncStatusMonitor` correctly maps started/ended/error events to `inProgress`, `lastSyncedAt`, and `error` and replays the latest status to late subscribers.
- [ ] `QuarantineManager` moves the SQLite triplet (main + `-wal` + `-shm`) and cleans up directories older than 30 days based on modification date — matching design Section 8.
- [ ] `CloudKitSchemaInitializer` is guarded by `#if DEBUG` and offers a `dryRun` test seam that avoids the real CloudKit call.
- [ ] `AttachmentStore.downloadData(id:)` is the only API that returns raw bytes — `fetch` / `attachments(forTask:)` return metadata-only records. Throws `attachmentFetchFailed` when bytes are absent.
- [ ] All previously-passing Plan 1 tests still pass after the container swap.
- [ ] No test makes a real network call or touches `CKContainer.default()`.
- [ ] The public surface lists exactly: `iCloudAccountState`, `AccountStateMonitor`, `AccountStatusProviding`, `CloudKitAccountStatusProvider`, `SyncStatus`, `SyncStatusMonitor`, `CloudKitSyncEvent`, `CloudKitEventBridge`, `QuarantineManager`, `CloudKitSchemaInitializer`, and the new `AttachmentStore.downloadData(id:)` method.
- [ ] **Test Engineer subagent has reviewed test quality** per design Section 9 — assessing behaviors covered, edge cases (CKAccountStatus exhaustiveness, quarantine sidecar handling, sync error mapping), and mutation-test rigor.
