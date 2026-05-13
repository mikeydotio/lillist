import Testing
import Foundation
@testable import LillistCore

@Suite("SyncStatusMonitor")
struct SyncStatusMonitorTests {
    @Test("Initial status is idle")
    func initial() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        #expect(await monitor.currentStatus == .idle)
    }

    @Test("Setup-started event sets inProgress to true")
    func setupStarted() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        // Let the consumer task subscribe to the bridge before we record.
        for _ in 0..<5 { await Task.yield() }
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        for _ in 0..<5 { await Task.yield() }
        let status = await monitor.currentStatus
        #expect(status.inProgress == true)
        #expect(status.error == nil)
    }

    @Test("Successful import completion clears inProgress and sets lastSyncedAt")
    func importCompletes() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        for _ in 0..<5 { await Task.yield() }
        let end = Date(timeIntervalSince1970: 2_000_000)
        await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        for _ in 0..<5 { await Task.yield() }
        await bridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        for _ in 0..<5 { await Task.yield() }
        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.lastSyncedAt == end)
        #expect(status.error == nil)
    }

    @Test("Failed export records the error and clears inProgress")
    func exportFails() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        for _ in 0..<5 { await Task.yield() }
        let err = LillistError.syncFailure(underlying: "network down")
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        for _ in 0..<5 { await Task.yield() }
        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err))
        for _ in 0..<5 { await Task.yield() }
        let status = await monitor.currentStatus
        #expect(status.inProgress == false)
        #expect(status.error == err)
    }

    @Test("Status stream yields updates")
    func statusStream() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        for _ in 0..<5 { await Task.yield() }
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()
        #expect(next?.inProgress == true)
    }
}
