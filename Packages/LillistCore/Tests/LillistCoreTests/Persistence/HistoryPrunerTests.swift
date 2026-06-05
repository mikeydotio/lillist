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

    @Test("localOnly: sweep prunes history and stores a token")
    func prunesLocalOnly() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        let didPrune = try await pruner.sweep()
        #expect(didPrune == true)
        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) != nil)
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
        let second = try await pruner.sweep()
        #expect(second == true)
    }
}
