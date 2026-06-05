import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Stands in for the `HistoryPruner.sweep()` call `AppEnvironment.bootstrap()`
/// makes — the app-target bootstrap can't be unit-tested (no app host), so
/// this LillistCore test is the behavioral contract the launch path relies on.
@Suite("HistoryPruner launch contract")
struct HistoryPrunerLaunchTests {
    @Test("sweep() at launch prunes a localOnly store and is a no-op for iCloudSync")
    func launchSweepBehavesByMode() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-hist-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Lillist.sqlite")
        let p = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "launch")

        let defaults = UserDefaults(suiteName: "history-launch-\(UUID().uuidString)")!
        // Exactly the convenience-init + sweep the bootstrap path uses.
        let localPruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        #expect(try await localPruner.sweep() == true)

        let cloudPruner = HistoryPruner(persistence: p, syncMode: .iCloudSync, defaults: defaults)
        #expect(try await cloudPruner.sweep() == false)
    }
}
