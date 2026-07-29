import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Stands in for the `HistoryPruner.sweep()` call `AppEnvironment.bootstrap()`
/// makes — the app-target bootstrap can't be unit-tested (no app host), so
/// this LillistCore test is the behavioral contract the launch path relies on.
@Suite("HistoryPruner launch contract")
struct HistoryPrunerLaunchTests {
    @Test("sweep() at launch prunes a localOnly store once every consumer has caught up, and is a no-op for iCloudSync")
    func launchSweepBehavesByMode() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-hist-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Lillist.sqlite")
        let p = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "launch")
        _ = try await store.create(title: "launch2")

        let suite = "history-launch-\(UUID().uuidString)"
        // Exactly what bootstrap()'s catch-up sequence produces before the
        // sweep call: every registered consumer has processed everything
        // currently in history.
        let latestToken: NSPersistentHistoryToken = try await {
            let ctx = p.makeBackgroundContext()
            let token: NSPersistentHistoryToken? = try await ctx.perform {
                let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
                let result = try ctx.execute(req) as? NSPersistentHistoryResult
                return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
            }
            return try #require(token)
        }()
        for id in HistoryConsumerID.allCases {
            PersistentHistoryTokenStore(suiteName: suite, consumer: id).lastToken = latestToken
        }

        let registry = WatermarkRegistry(suiteName: suite)
        let localPruner = HistoryPruner(persistence: p, syncMode: .localOnly, registry: registry)
        #expect(try await localPruner.sweep() == .pruned)

        let cloudPruner = HistoryPruner(persistence: p, syncMode: .iCloudSync, registry: registry)
        #expect(try await cloudPruner.sweep() == .skippedICloudSync)
    }
}
