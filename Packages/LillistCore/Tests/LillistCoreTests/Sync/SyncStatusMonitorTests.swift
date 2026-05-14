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

        // Use the monitor's statusStream as the synchronization primitive.
        // `iterator.next()` on the post-record yield is a real happens-before:
        // it only returns after `apply` has updated `currentStatus` and
        // yielded to subscribers. No yield-polling needed.
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay (state .idle)

        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()

        #expect(next?.inProgress == true)
        #expect(next?.error == nil)
        // currentStatus is also consistent now that we waited for apply.
        let status = await monitor.currentStatus
        #expect(status.inProgress == true)
        #expect(status.error == nil)
    }

    @Test("Successful import completion clears inProgress and sets lastSyncedAt")
    func importCompletes() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let end = Date(timeIntervalSince1970: 2_000_000)
        await bridge.recordEvent(.init(type: .import, started: true, endedAt: nil, error: nil))
        _ = await iterator.next() // state after start

        await bridge.recordEvent(.init(type: .import, started: false, endedAt: end, error: nil))
        let final = await iterator.next() // state after end

        #expect(final?.inProgress == false)
        #expect(final?.lastSyncedAt == end)
        #expect(final?.error == nil)
    }

    @Test("Failed export records the error and clears inProgress")
    func exportFails() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()

        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay

        let err = LillistError.syncFailure(underlying: "network down")
        await bridge.recordEvent(.init(type: .export, started: true, endedAt: nil, error: nil))
        _ = await iterator.next() // state after start

        await bridge.recordEvent(.init(type: .export, started: false, endedAt: Date(), error: err))
        let final = await iterator.next() // state after failure

        #expect(final?.inProgress == false)
        #expect(final?.error == err)
    }

    @Test("Status stream yields updates")
    func statusStream() async throws {
        let bridge = CloudKitEventBridge()
        let monitor = SyncStatusMonitor(bridge: bridge)
        await monitor.start()
        var iterator = await monitor.statusStream.makeAsyncIterator()
        _ = await iterator.next() // initial replay
        await bridge.recordEvent(.init(type: .setup, started: true, endedAt: nil, error: nil))
        let next = await iterator.next()
        #expect(next?.inProgress == true)
    }
}
