import Testing
import CoreData
import Foundation
@testable import LillistCore

/// Plan 21 Wave 2 — `PersistenceHost` tests. The host's reconfigure
/// path touches the live container, so the live tests share the same
/// `liveSwapAllowed` gate as `StoreLevelModeSwapSpike` (swift-test
/// crashes during `NSCloudKitMirroringDelegate` teardown when there's
/// no `CFBundleIdentifier` — see that file's header for the long
/// version).
@Suite("PersistenceHost", .serialized)
struct PersistenceHostTests {
    private static var liveSwapAllowed: Bool {
        Bundle.main.bundleIdentifier?.isEmpty == false
    }

    private static func freshStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceHostTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lillist.sqlite")
    }

    @Test("init records the initial mode")
    func initRecordsMode() async throws {
        let p = try await PersistenceController(configuration: .inMemory.withSyncMode(.localOnly))
        let host = PersistenceHost(controller: p, initialMode: .localOnly)
        #expect(await host.currentMode == .localOnly)
    }

    @Test("reconfigure to the same mode is a no-op (idempotent)")
    func reconfigureSameModeIsNoop() async throws {
        let p = try await PersistenceController(configuration: .inMemory.withSyncMode(.iCloudSync))
        let host = PersistenceHost(controller: p, initialMode: .iCloudSync)
        try await host.reconfigure(to: .iCloudSync)
        #expect(await host.currentMode == .iCloudSync)
    }

    @Test("Reconfigure swaps mode and preserves data", .enabled(if: liveSwapAllowed))
    func reconfigureSwapsAndPreservesData() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let controller = await host.controller
        // Seed one task so we can prove data survives.
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "host-test"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }

        try await host.reconfigure(to: .localOnly)
        #expect(await host.currentMode == .localOnly)

        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(count == 1)
    }
}
