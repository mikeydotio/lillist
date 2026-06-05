import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("HistoryPruner")
struct HistoryPrunerTests {
    private func onDiskStore(syncMode: SyncMode) async throws -> (PersistenceController, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-hist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Lillist.sqlite")
        let p = try await PersistenceController(configuration: .onDisk(url: url, syncMode: syncMode))
        return (p, dir)
    }

    /// Returns the count of all persistent-history transactions from the
    /// beginning of time — i.e., every transaction recorded since the store
    /// was created.  Runs on a fresh background context so it doesn't
    /// interfere with any in-flight context work.
    private func historyTransactionCount(_ p: PersistenceController) async throws -> Int {
        let ctx = p.makeBackgroundContext()
        return try await ctx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            let txns = (result?.result as? [NSPersistentHistoryTransaction]) ?? []
            return txns.count
        }
    }

    @Test("localOnly: sweep prunes history and stores a token")
    func prunesLocalOnly() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")

        let preSweepCount = try await historyTransactionCount(p)
        #expect(preSweepCount > 0, "Seeded writes must have produced history transactions")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        let didPrune = try await pruner.sweep()
        #expect(didPrune == true)
        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) != nil)

        let postSweepCount = try await historyTransactionCount(p)
        // Observed on this platform (arm64e-apple-macos): 2 task creates
        // produce pre=2 history transactions; after sweep(), post=1 (the
        // deleteHistory call itself is recorded as a new transaction, so
        // the original 2 are removed but 1 residual remains). The strict
        // `<` catches the failure mode where deleteHistory is a no-op:
        // in that case post would equal pre and the assertion fires.
        #expect(postSweepCount < preSweepCount,
                "Post-sweep transaction count (\(postSweepCount)) must be less than pre-sweep count (\(preSweepCount))")
    }

    @Test("iCloudSync: sweep is a no-op (CloudKit owns pruning)")
    func skipsICloudSync() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .iCloudSync, defaults: defaults)
        let didPrune = try await pruner.sweep()
        #expect(didPrune == false)
        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) == nil)
    }

    @Test("Second sweep is idempotent")
    func idempotent() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        _ = try await pruner.sweep()

        let tokenAfterFirstSweep = defaults.data(forKey: HistoryPruner.tokenDefaultsKey)
        let countAfterFirstSweep = try await historyTransactionCount(p)

        // Second sweep with no new writes must not advance the high-water
        // token (same Data blob in defaults) and must not change the
        // transaction count — there is nothing new to prune.
        let second = try await pruner.sweep()
        #expect(second == true)

        let tokenAfterSecondSweep = defaults.data(forKey: HistoryPruner.tokenDefaultsKey)
        let countAfterSecondSweep = try await historyTransactionCount(p)

        #expect(tokenAfterSecondSweep == tokenAfterFirstSweep,
                "Second sweep must not advance the high-water token when no new writes occurred")
        #expect(countAfterSecondSweep == countAfterFirstSweep,
                "Second sweep must leave the transaction count unchanged (nothing new to prune)")
    }
}
