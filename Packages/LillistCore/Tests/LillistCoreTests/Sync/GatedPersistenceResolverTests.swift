import XCTest
@testable import LillistCore

/// Direct coverage of the gate-aware store-configuration resolution that
/// `IntentSupport.makePersistence()` (App Intents) and `ShareRootView.save()`
/// (Share Extension) both delegate to. The MigrationGate abort branch — which
/// surfaces `LillistError.storeUnavailable` so callers retry instead of racing
/// a half-swapped store — was previously unreachable by any test because both
/// callers constructed the gate inline against the real App Group container.
final class GatedPersistenceResolverTests: XCTestCase {

    /// A fresh identifier per test invocation, matching the established
    /// UUID-suffixed-suite + `removePersistentDomain` precedent used
    /// throughout this test target (`MigrationCoordinatorTests`,
    /// `MigrationGateTests`, `SyncModeStoreTests`, etc.).
    ///
    /// Every test in this file used to share one literal
    /// `"group.app.lillist.tests.gate"` string for BOTH the
    /// `SyncModeStore(suiteName:)` backing (real, disk-backed,
    /// cross-process `UserDefaults` state keyed by that string) and the
    /// `appGroupID` handed to `GatedPersistenceResolver` (which reaches
    /// real `StoreLocation.resolve`'s unsandboxed `containerURL` lookup).
    /// Under `swift test --parallel`, XCTest cases run in separate worker
    /// processes — sharing one suite name let one test's `setMode(_:)`
    /// write land between another test's `setMode(_:)` + read, producing
    /// a nondeterministic assertion failure (LIL-79). Every test now gets
    /// its own identifier, eliminating the shared-state surface entirely
    /// rather than trying to serialize around it.
    private func freshAppGroupID() -> String {
        let id = "group.app.lillist.tests.gate-\(UUID().uuidString)"
        UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
        return id
    }

    func test_idleJournal_resolvesConfigForCurrentMode() async throws {
        let appGroupID = freshAppGroupID()
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            role: .extensionProcess,
            journal: journal,
            modeStore: modeStore
        )

        let config = try await resolver.resolveStoreConfiguration()

        XCTAssertEqual(config.syncMode, .localOnly)
    }

    func test_inFlightJournal_throwsStoreUnavailableWithGateMessage() async throws {
        let appGroupID = freshAppGroupID()
        let journal = InMemoryMigrationJournalStore(
            initial: MigrationJournal(state: .reconfiguringStore)
        )
        let modeStore = SyncModeStore(suiteName: appGroupID)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            role: .extensionProcess,
            journal: journal,
            modeStore: modeStore
        )

        do {
            _ = try await resolver.resolveStoreConfiguration()
            XCTFail("Expected storeUnavailable while a migration is in flight")
        } catch let LillistError.storeUnavailable(reason) {
            XCTAssertEqual(
                reason,
                "Sync settings are being changed. Try again in a moment."
            )
        }
    }

    func test_makePersistence_idleJournal_returnsUsableController() async throws {
        // The `makeController` seam lets us assert end-to-end resolution +
        // controller construction without standing up the real App Group.
        let appGroupID = freshAppGroupID()
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            role: .extensionProcess,
            journal: journal,
            modeStore: modeStore
        )

        var seenMode: SyncMode?
        let controller = try await resolver.makePersistence { config in
            seenMode = config.syncMode
            return try await PersistenceController(configuration: .inMemory)
        }

        XCTAssertEqual(seenMode, .localOnly)
        // Smoke-check the returned controller is live.
        let store = TaskStore(persistence: controller)
        let id = try await store.create(title: "gate ok")
        let record = try await store.fetch(id: id)
        XCTAssertEqual(record.title, "gate ok")
    }

    func test_X15_extensionAndWidgetRolesSuppressMirroring_mainAppDoesNot() async throws {
        let appGroupID = freshAppGroupID()
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.iCloudSync)

        for role: StoreLocation.Role in [.extensionProcess, .widget, .cli] {
            let resolver = GatedPersistenceResolver(
                appGroupID: appGroupID,
                role: role,
                journal: journal,
                modeStore: modeStore
            )
            let config = try await resolver.resolveStoreConfiguration()
            XCTAssertFalse(config.armsCloudKitMirroring, "role \(role) must not arm mirroring")
        }

        let mainAppResolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            role: .mainApp,
            journal: journal,
            modeStore: modeStore
        )
        let mainAppConfig = try await mainAppResolver.resolveStoreConfiguration()
        XCTAssertTrue(mainAppConfig.armsCloudKitMirroring)
    }
}
