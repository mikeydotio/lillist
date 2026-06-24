import XCTest
@testable import LillistCore

/// Direct coverage of the gate-aware store-configuration resolution that
/// `IntentSupport.makePersistence()` (App Intents) and `ShareRootView.save()`
/// (Share Extension) both delegate to. The MigrationGate abort branch — which
/// surfaces `LillistError.storeUnavailable` so callers retry instead of racing
/// a half-swapped store — was previously unreachable by any test because both
/// callers constructed the gate inline against the real App Group container.
final class GatedPersistenceResolverTests: XCTestCase {

    private let appGroupID = "group.app.lillist.tests.gate"

    func test_idleJournal_resolvesConfigForCurrentMode() async throws {
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
            journal: journal,
            modeStore: modeStore
        )

        let config = try await resolver.resolveStoreConfiguration()

        XCTAssertEqual(config.syncMode, .localOnly)
    }

    func test_inFlightJournal_throwsStoreUnavailableWithGateMessage() async throws {
        let journal = InMemoryMigrationJournalStore(
            initial: MigrationJournal(state: .reconfiguringStore)
        )
        let modeStore = SyncModeStore(suiteName: appGroupID)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
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
        let journal = InMemoryMigrationJournalStore(initial: .idle)
        let modeStore = SyncModeStore(suiteName: appGroupID)
        await modeStore.setMode(.localOnly)
        let resolver = GatedPersistenceResolver(
            appGroupID: appGroupID,
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
}
