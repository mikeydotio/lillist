import Testing
import Foundation
import CoreData
@testable import LillistCore

/// `X12`'s named failure mode, exercised end-to-end through `HistoryPruner`
/// (not just `WatermarkRegistry.pruneBoundary(in:)` in isolation — see
/// `WatermarkRegistryTests` for the unit-level cases). Before this plan,
/// `HistoryPruner.sweep()` deleted everything before "now," trusting every
/// consumer to have already caught up via `bootstrap()`'s call ordering. A
/// Share Extension write landing while the main app (and therefore, e.g.,
/// `DiagnosticHistoryObserver`) was closed could be pruned before that
/// consumer ever saw it. These tests prove the registry-gated sweep can no
/// longer do that, regardless of which consumer is behind or missing.
@Suite("X12: HistoryPruner respects the slowest/missing consumer's watermark")
struct X12WatermarkGatedPruningTests {
    private func onDiskStore() async throws -> (PersistenceController, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-x12-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Lillist.sqlite")
        let p = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        return (p, dir)
    }

    private func latestHistoryToken(_ p: PersistenceController) async throws -> NSPersistentHistoryToken {
        let ctx = p.makeBackgroundContext()
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }
        return try #require(token)
    }

    private func historyCount(_ p: PersistenceController, after token: NSPersistentHistoryToken?) async throws -> Int {
        let ctx = p.makeBackgroundContext()
        return try await ctx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.count ?? 0
        }
    }

    @Test("a lagging consumer's still-unconsumed history survives the sweep")
    func laggingConsumerHistorySurvivesSweep() async throws {
        let (p, dir) = try await onDiskStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)

        _ = try await store.create(title: "seen-by-every-consumer")
        let earlyToken = try await latestHistoryToken(p)
        // Simulates a Share Extension write landing while the main app
        // (and therefore its DiagnosticHistoryObserver) was closed: this
        // create exists in history, but the diagnostics consumer has not
        // caught up past `earlyToken` yet.
        _ = try await store.create(title: "not-yet-seen-by-diagnostics")

        let suite = "x12-test-\(UUID().uuidString)"
        PersistentHistoryTokenStore(suiteName: suite, consumer: .remoteChangeReconciler).lastToken = try await latestHistoryToken(p)
        PersistentHistoryTokenStore(suiteName: suite, consumer: .backup).lastToken = try await latestHistoryToken(p)
        PersistentHistoryTokenStore(suiteName: suite, consumer: .diagnostics).lastToken = earlyToken

        let beforeCount = try await historyCount(p, after: earlyToken)
        #expect(beforeCount > 0, "the not-yet-seen create must exist before the sweep")

        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: WatermarkRegistry(suiteName: suite))
        let outcome = try await pruner.sweep()
        #expect(outcome == .pruned, "the sweep still runs — it prunes to the min watermark (diagnostics'), not to nothing")

        let afterCount = try await historyCount(p, after: earlyToken)
        #expect(afterCount > 0, "the lagging consumer's own unconsumed history must survive the sweep")
        #expect(afterCount >= beforeCount, "nothing the lagging consumer hadn't seen yet may be removed by this sweep")
    }

    @Test("a brand-new, never-run consumer blocks the sweep even when every other consumer is fully caught up")
    func freshConsumerAmongCaughtUpOnesBlocksSweep() async throws {
        let (p, dir) = try await onDiskStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")
        let latest = try await latestHistoryToken(p)
        let preSweepCount = try await historyCount(p, after: nil)

        let suite = "x12-test-\(UUID().uuidString)"
        // remoteChangeReconciler and backup are fully caught up; diagnostics
        // has literally never run yet (its watermark stays nil — a brand
        // new consumer added after this launch's history already started
        // accumulating, or right after a reset before its first catch-up).
        PersistentHistoryTokenStore(suiteName: suite, consumer: .remoteChangeReconciler).lastToken = latest
        PersistentHistoryTokenStore(suiteName: suite, consumer: .backup).lastToken = latest

        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: WatermarkRegistry(suiteName: suite))
        let outcome = try await pruner.sweep()

        #expect(outcome == .skippedNoSafeBoundary)
        #expect(try await historyCount(p, after: nil) == preSweepCount, "nothing may be deleted while any registered consumer has no watermark yet")
    }
}
