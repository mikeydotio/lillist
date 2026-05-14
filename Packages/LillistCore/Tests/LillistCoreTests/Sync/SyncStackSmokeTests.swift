import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("Sync stack smoke")
struct SyncStackSmokeTests {
    @Test("Bridge → monitor pipeline reflects a simulated import completion")
    func endToEnd() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        let monitor = SyncStatusMonitor(bridge: controller.cloudKitEventBridge)
        await monitor.start()

        // Use the monitor's statusStream as the deterministic sync primitive
        // between the bridge's producer and the test's assertions.
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay (state .idle)

        let end = Date(timeIntervalSince1970: 3_000_000)
        await controller.cloudKitEventBridge.recordEvent(
            .init(type: .import, started: true, endedAt: nil, error: nil)
        )
        _ = await iterator.next() // state after start

        await controller.cloudKitEventBridge.recordEvent(
            .init(type: .import, started: false, endedAt: end, error: nil)
        )
        let final = await iterator.next() // state after end

        #expect(final?.inProgress == false)
        #expect(final?.lastSyncedAt == end)
        #expect(final?.error == nil)
    }

    @Test("Account monitor + sync monitor coexist without crashing")
    func coexistence() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        actor StaticProvider: AccountStatusProviding {
            func accountStatus() async throws -> CKAccountStatus { .available }
        }
        let accountMonitor = AccountStateMonitor(provider: StaticProvider())
        let syncMonitor = SyncStatusMonitor(bridge: controller.cloudKitEventBridge)
        try await accountMonitor.refresh()
        await syncMonitor.start()
        #expect(await accountMonitor.currentState == .available)
        #expect(await syncMonitor.currentStatus == .idle)
    }
}
