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
    /// was created. Runs on a fresh background context so it doesn't
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

    /// The token of the most recently recorded transaction — what a fully
    /// caught-up consumer's own watermark would read after processing
    /// everything so far.
    private func latestHistoryToken(_ p: PersistenceController) async throws -> NSPersistentHistoryToken {
        let ctx = p.makeBackgroundContext()
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }
        return try #require(token)
    }

    /// Marks every registered consumer as fully caught up to `token` in the
    /// given suite — the shape `bootstrap()`'s catch-up sequence produces
    /// when every consumer has processed everything currently in history.
    private func markAllConsumersCaughtUp(to token: NSPersistentHistoryToken, suite: String) {
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = token
        }
    }

    @Test("localOnly: sweep prunes history once every consumer has caught up")
    func prunesLocalOnly() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")
        _ = try await store.create(title: "c")

        let preSweepCount = try await historyTransactionCount(p)
        #expect(preSweepCount > 0, "Seeded writes must have produced history transactions")

        let suite = "history-pruner-test-\(UUID().uuidString)"
        markAllConsumersCaughtUp(to: try await latestHistoryToken(p), suite: suite)
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: WatermarkRegistry(suiteName: suite))
        let outcome = try await pruner.sweep()
        #expect(outcome == .pruned)

        let postSweepCount = try await historyTransactionCount(p)
        // deleteHistory(before:) is exclusive of its boundary, and the
        // delete request itself is recorded as a new transaction — with
        // three writes pruned to the latest one's own watermark, the
        // surviving count is [the boundary transaction] + [the delete's own
        // transaction], strictly fewer than the three originals.
        #expect(postSweepCount < preSweepCount,
                "Post-sweep transaction count (\(postSweepCount)) must be less than pre-sweep count (\(preSweepCount))")
    }

    @Test("iCloudSync: sweep is a no-op (CloudKit owns pruning)")
    func skipsICloudSync() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")

        let suite = "history-pruner-test-\(UUID().uuidString)"
        let pruner = HistoryPruner(persistence: p, syncMode: .iCloudSync, registry: WatermarkRegistry(suiteName: suite))
        let outcome = try await pruner.sweep()
        #expect(outcome == .skippedICloudSync)
    }

    @Test("localOnly with no consumer ever caught up: sweep is a safe no-op, never guesses a boundary")
    func skipsWhenNoConsumerHasCaughtUp() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        let preSweepCount = try await historyTransactionCount(p)

        let suite = "history-pruner-test-\(UUID().uuidString)"
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: WatermarkRegistry(suiteName: suite))
        let outcome = try await pruner.sweep()

        #expect(outcome == .skippedNoSafeBoundary)
        #expect(try await historyTransactionCount(p) == preSweepCount, "Nothing must be deleted when no consumer has a watermark yet")
    }

    @Test("A second sweep with unchanged consumer watermarks keeps succeeding, not regressing to .skippedNoSafeBoundary")
    func idempotent() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")
        _ = try await store.create(title: "c")

        let suite = "history-pruner-test-\(UUID().uuidString)"
        markAllConsumersCaughtUp(to: try await latestHistoryToken(p), suite: suite)
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: WatermarkRegistry(suiteName: suite))

        #expect(try await pruner.sweep() == .pruned)
        // Consumer watermarks are unchanged (no simulated re-catch-up
        // between calls) — the boundary transaction itself must still be
        // present and locatable, so a second, otherwise-idle sweep keeps
        // succeeding rather than silently losing its anchor.
        #expect(try await pruner.sweep() == .pruned,
                "a second sweep with the same, still-locatable consumer watermarks must keep succeeding")
    }
}
