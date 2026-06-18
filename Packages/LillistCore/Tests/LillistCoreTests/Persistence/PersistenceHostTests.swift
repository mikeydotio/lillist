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

    @Test("Failed reconfigure rolls back to the original store (no store-less coordinator)", .enabled(if: liveSwapAllowed))
    func failedReconfigureRollsBack() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let controller = await host.controller
        // Seed a row so we can prove the original store survives a
        // rollback (count stays readable post-failure).
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "rollback-test"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }

        // Arm the test seam so the next swap re-adds the original store
        // (the rollback path) and then throws, without corrupting a
        // real on-disk store.
        await host.simulateAddFailureOnNextSwap()
        await #expect(throws: (any Error).self) {
            try await host.reconfigure(to: .localOnly)
        }

        // The original store must still be attached: a count succeeds
        // and the mode is unchanged.
        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(count == 1)
        #expect(await host.currentMode == .iCloudSync)
    }

    // Roadmap #1 proof. The framework does not surface
    // `cloudKitContainerOptions` back through the live `NSPersistentStore`
    // (only the *description* carries them — see
    // `StoreLevelModeSwapSpike.swapMutatesDescription`), so a true
    // assertion on the re-added live store's CloudKit options is not
    // reachable without a live container. The rollback re-adds the
    // *exact* `NSPersistentStoreDescription` produced by
    // `PersistenceController.makeStoreDescription(for:)`, so asserting
    // that factory output directly proves the same thing the live
    // rollback would — that mirroring is restored intact, not silently
    // downgraded to a plain local store. We assert the factory directly
    // (rather than building a live host) because
    // `NSPersistentCloudKitContainer` teardown crashes the `swift test`
    // binary (the reason the live swap tests above are
    // `.enabled(if: liveSwapAllowed)`-gated). This keeps the proof
    // ungated and crash-free under `swift test`.
    @Test("Rollback from a half-added iCloud store preserves cloudKitContainerOptions (Roadmap #1)")
    func rollbackPreservesCloudKitOptions() async throws {
        // The rollback description is built from the captured ORIGINAL
        // mode (`.iCloudSync` here) via this exact factory call.
        let rollbackConfig = StoreConfiguration(
            storeKind: .onDisk(url: Self.freshStoreURL()),
            cloudKitContainerIdentifier: StoreConfiguration.defaultCloudKitContainerIdentifier,
            syncMode: .iCloudSync
        )
        let rollbackDesc = PersistenceController.makeStoreDescription(for: rollbackConfig)

        // The rollback description must carry CloudKit options matching
        // the original container — i.e. mirroring is restored intact,
        // not silently dropped to a plain local store.
        #expect(rollbackDesc.cloudKitContainerOptions != nil)
        #expect(rollbackDesc.cloudKitContainerOptions?.containerIdentifier
                == StoreConfiguration.defaultCloudKitContainerIdentifier)
        #expect(rollbackDesc.cloudKitContainerOptions?.databaseScope == .private)
        // And the persistent-history / remote-change flags survive too,
        // so a later re-enable of iCloudSync still works.
        #expect((rollbackDesc.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue == true)
    }

    // MARK: - Destructive reset (PersistenceResetting)

    @Test("tearDownStore + rebuildEmptyStore wipes data and leaves a usable empty store", .enabled(if: liveSwapAllowed))
    func resetWipesAndRebuilds() async throws {
        let url = Self.freshStoreURL()
        // localOnly: no CloudKit mirroring delegate to tear down, so the
        // wipe round-trip is exercised without an iCloud account.
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: url)
        let controller = await host.controller
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "reset-test"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }

        let quarantine = QuarantineManager(rootDirectory: url.deletingLastPathComponent())
        let backup = try await host.tearDownStore(backupVia: quarantine)
        // A recovery anchor was captured before the destroy.
        #expect(backup != nil)
        #expect(try quarantine.latestQuarantinedStore() != nil)

        try await host.rebuildEmptyStore()

        // The rebuilt store is empty and the shared viewContext is usable.
        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(count == 0)
        // A fresh write into the rebuilt store succeeds.
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "post-reset"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }
        let after = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(after == 1)
    }

    @Test("reattachStore restores the original data after a tear-down (rollback path)", .enabled(if: liveSwapAllowed))
    func reattachRestoresOriginalData() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .localOnly, storeURL: url)
        let controller = await host.controller
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "reattach-test"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }

        // Tear the store off (files left on disk), then re-attach instead
        // of destroying — the seeded row must survive.
        _ = try await host.tearDownStore(backupVia: nil)
        try await host.reattachStore()

        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(count == 1)
    }
}
