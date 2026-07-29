import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Data-sync-hardening `X11`/`X12`/`L7`. Replaces `HistoryWatermarksTests`
/// (`3b`'s narrower seam, now retired) — the `clearAll` cases below are the
/// direct successors of that file's own tests, proving reset-clear parity;
/// the `pruneBoundary` cases are new, covering the min-over-consumers
/// semantics table in the plan doc.
@Suite("WatermarkRegistry")
struct WatermarkRegistryTests {
    private static func freshSuiteName() -> String {
        let suite = "WatermarkRegistryTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    /// Writes one task per title to a fresh in-memory store and returns the
    /// persistent-history token recorded immediately after each write, in
    /// order — `tokens[0]` is the oldest, `tokens.last` the newest.
    private func historyTokens(afterWriting titles: [String]) async throws -> (PersistenceController, [NSPersistentHistoryToken]) {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        var tokens: [NSPersistentHistoryToken] = []
        for title in titles {
            _ = try await store.create(title: title)
            let ctx = p.makeBackgroundContext()
            let token: NSPersistentHistoryToken? = try await ctx.perform {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
                let result = try ctx.execute(request) as? NSPersistentHistoryResult
                return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
            }
            tokens.append(try #require(token, "Write #\(tokens.count + 1) (\(title)) must produce a history token"))
        }
        return (p, tokens)
    }

    // MARK: - clearAll (X11 parity with the retired HistoryWatermarks)

    @Test("clearAll nils every registered consumer's watermark")
    func clearAllClearsEveryConsumer() async throws {
        let suite = Self.freshSuiteName()
        let (_, tokens) = try await historyTokens(afterWriting: ["a"])
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = tokens[0]
        }

        WatermarkRegistry(suiteName: suite).clearAll()

        for id in HistoryConsumerID.allCases {
            #expect(PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken == nil, "\(id) watermark must be nil after clearAll")
        }
    }

    @Test("clearAll removes HistoryPruner's retired bookkeeping key too")
    func clearAllRemovesLegacyPrunerKey() async throws {
        let suite = Self.freshSuiteName()
        let defaults = try #require(UserDefaults(suiteName: suite))
        let (_, tokens) = try await historyTokens(afterWriting: ["a"])
        let archived = try NSKeyedArchiver.archivedData(withRootObject: tokens[0], requiringSecureCoding: true)
        defaults.set(archived, forKey: "app.lillist.history.prunedToken")

        WatermarkRegistry(suiteName: suite).clearAll()

        #expect(defaults.data(forKey: "app.lillist.history.prunedToken") == nil)
    }

    @Test("clearAll on already-empty watermarks is a harmless no-op")
    func clearAllOnEmptyIsNoop() {
        let suite = Self.freshSuiteName()
        WatermarkRegistry(suiteName: suite).clearAll()
        for id in HistoryConsumerID.allCases {
            #expect(PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken == nil)
        }
    }

    // MARK: - watermarks enumeration

    @Test("watermarks enumerates every HistoryConsumerID exactly once")
    func watermarksEnumeratesEveryConsumer() {
        let suite = Self.freshSuiteName()
        let ids = WatermarkRegistry(suiteName: suite).watermarks.map(\.id)
        #expect(Set(ids) == Set(HistoryConsumerID.allCases))
        #expect(ids.count == HistoryConsumerID.allCases.count)
    }

    // MARK: - pruneBoundary (X12/L7)

    @Test("pruneBoundary resolves to the earliest of several distinct consumer watermarks")
    func pruneBoundaryResolvesToEarliestWatermark() async throws {
        let suite = Self.freshSuiteName()
        let (p, tokens) = try await historyTokens(afterWriting: ["a", "b", "c"])
        // Two consumers are fully caught up (newest token); one (diagnostics)
        // is lagging behind at the oldest token — the min must be its token,
        // not the newest.
        PersistentHistoryTokenStore(suiteName: suite, consumer: .remoteChangeReconciler).lastToken = tokens[2]
        PersistentHistoryTokenStore(suiteName: suite, consumer: .diagnostics).lastToken = tokens[0]
        PersistentHistoryTokenStore(suiteName: suite, consumer: .backup).lastToken = tokens[2]

        let registry = WatermarkRegistry(suiteName: suite)
        let ctx = p.makeBackgroundContext()
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }

        #expect(boundary == .boundary(tokens[0]))
    }

    @Test("pruneBoundary is .unresolved when any registered consumer has no watermark yet")
    func pruneBoundaryUnresolvedOnFreshConsumer() async throws {
        let suite = Self.freshSuiteName()
        let (p, tokens) = try await historyTokens(afterWriting: ["a"])
        // remoteChangeReconciler and backup caught up; diagnostics never ran.
        PersistentHistoryTokenStore(suiteName: suite, consumer: .remoteChangeReconciler).lastToken = tokens[0]
        PersistentHistoryTokenStore(suiteName: suite, consumer: .backup).lastToken = tokens[0]

        let registry = WatermarkRegistry(suiteName: suite)
        let ctx = p.makeBackgroundContext()
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }

        #expect(boundary == .unresolved)
    }

    @Test("pruneBoundary is .unresolved on a truly fresh store (no writes, no watermarks)")
    func pruneBoundaryUnresolvedOnFreshStore() async throws {
        let suite = Self.freshSuiteName()
        let p = try await TestStore.make()
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = nil
        }

        let registry = WatermarkRegistry(suiteName: suite)
        let ctx = p.makeBackgroundContext()
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }

        #expect(boundary == .unresolved, "the fresh-consumer short-circuit fires before the history fetch")
    }

    @Test("pruneBoundary is .noHistory when every consumer has a watermark but the store retains no transactions")
    func pruneBoundaryNoHistoryWithStaleWatermarksOnFreshStore() async throws {
        let suite = Self.freshSuiteName()
        let p = try await TestStore.make()   // fresh, unwritten store
        // Simulate stale watermarks surviving a destructive reset that
        // should have called WatermarkRegistry.clearAll() (X11) but didn't
        // — the watermark VALUES are irrelevant here (this store's history
        // is empty regardless of what any consumer claims), only that
        // every consumer has SOME non-nil watermark so the fresh-consumer
        // short-circuit doesn't fire first, exercising the distinct
        // "watermarks exist, history doesn't" branch instead.
        let (_, staleTokens) = try await historyTokens(afterWriting: ["stale"])
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = staleTokens[0]
        }

        let registry = WatermarkRegistry(suiteName: suite)
        let ctx = p.makeBackgroundContext()
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }

        #expect(boundary == .noHistory)
    }

    @Test("pruneBoundary is .unresolved when a watermark points to history already pruned by something else")
    func pruneBoundaryUnresolvedOnUnlocatableWatermark() async throws {
        let suite = Self.freshSuiteName()
        let (p, tokens) = try await historyTokens(afterWriting: ["a", "b", "c"])
        let ctx = p.makeBackgroundContext()
        // Simulate an external actor deleting history out from under a
        // lagging consumer — a destructive reset that bypassed
        // WatermarkRegistry.clearAll(), or CloudKit's own export-cursor
        // pruning racing a lagging consumer across a sync-mode round-trip
        // (see the plan doc's semantics table). Pruning before tokens[1]
        // removes tokens[0]'s own transaction entirely.
        try await ctx.perform {
            _ = try ctx.execute(NSPersistentHistoryChangeRequest.deleteHistory(before: tokens[1]))
        }
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = tokens[0]
        }

        let registry = WatermarkRegistry(suiteName: suite)
        let boundary = try await ctx.perform { try registry.pruneBoundary(in: ctx) }

        #expect(boundary == .unresolved)
    }
}
