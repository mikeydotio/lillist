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
        for _ in 0..<5 { await Task.yield() }

        let end = Date(timeIntervalSince1970: 3_000_000)
        await controller.cloudKitEventBridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        for _ in 0..<5 { await Task.yield() }
        await controller.cloudKitEventBridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        for _ in 0..<5 { await Task.yield() }

        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.lastSyncedAt == end)
        #expect(status.error == nil)
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
