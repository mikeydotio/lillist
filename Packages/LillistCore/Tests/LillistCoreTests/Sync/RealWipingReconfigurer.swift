import Foundation
import CoreData
@testable import LillistCore

/// A `PersistenceReconfiguring & PersistenceResetting` fake that wraps a
/// REAL `PersistenceController` and genuinely deletes every row on
/// `rebuildEmptyStore` — unlike `FakePersistenceReconfigurer`, which only
/// records that reset steps happened without touching any data.
///
/// Used to prove `S1`'s class-kill: `replaceLocalWithICloud` must
/// actually WIPE local rows before mirroring re-attaches, not merely
/// reconfigure in place (which would let local rows merge into iCloud
/// instead of being replaced). A fake that never really clears the store
/// would let that assertion pass regardless of whether the bug is
/// present — the same reasoning `RealWipingResetHost` in
/// `DataStoreResetServiceTests` documents for the equivalent `S9a` proof.
///
/// `reconfigure(to:)` does NOT touch a live `NSPersistentCloudKitContainer`
/// (that path crashes under `swift test` — see `StoreLevelModeSwapSpike`'s
/// header) — it only records the call and flips `mode`, exactly like
/// `FakePersistenceReconfigurer`.
actor RealWipingReconfigurer: PersistenceReconfiguring, PersistenceResetting {
    private let persistence: PersistenceController
    private(set) var mode: SyncMode
    private(set) var reconfigureCalls: [SyncMode] = []
    private(set) var resetSteps: [String] = []

    init(persistence: PersistenceController, initialMode: SyncMode) {
        self.persistence = persistence
        self.mode = initialMode
    }

    var currentMode: SyncMode { mode }

    func reconfigure(to newMode: SyncMode) async throws {
        reconfigureCalls.append(newMode)
        mode = newMode
    }

    func tearDownStore(backupVia quarantine: QuarantineManager?) async throws -> QuarantineManager.QuarantinedBackup? {
        resetSteps.append("tearDown")
        return nil
    }

    func rebuildEmptyStore() async throws {
        resetSteps.append("rebuild")
        let ctx = persistence.container.viewContext
        try await ctx.perform {
            for entityName in ["Attachment", "JournalEntry", "NotificationSpec", "LillistTask", "Tag", "Series", "SmartFilter"] {
                let req = NSFetchRequest<NSManagedObject>(entityName: entityName)
                for row in try ctx.fetch(req) {
                    ctx.delete(row)
                }
            }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    func reattachStore() async throws {
        resetSteps.append("reattach")
    }
}
