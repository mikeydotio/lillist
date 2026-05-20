import Testing
import Foundation
@testable import LillistCore

@Suite("SyncQuiesceMonitor")
struct SyncQuiesceMonitorTests {
    @Test("Quiesces immediately when no events ever fire")
    func quiescesWithNoEvents() async {
        let bridge = CloudKitEventBridge()
        let monitor = SyncQuiesceMonitor(bridge: bridge)
        let result = await monitor.waitForQuiesce(minQuietWindow: 0.1, hardTimeout: 5)
        #expect(result == .quiesced)
    }

    @Test("Times out when events arrive faster than the quiet window")
    func timesOutWhenChurning() async {
        let bridge = CloudKitEventBridge()
        let monitor = SyncQuiesceMonitor(bridge: bridge)
        // Kick off a churner that posts an event every 50ms while
        // the monitor is waiting with a 300ms quiet window and 0.5s
        // hard timeout.
        let churner = Task { [bridge] in
            for _ in 0..<20 {
                await bridge.recordEvent(CloudKitSyncEvent(type: .import, started: false, endedAt: Date(), error: nil))
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        defer { churner.cancel() }
        let result = await monitor.waitForQuiesce(minQuietWindow: 0.3, hardTimeout: 0.5)
        #expect(result == .timedOut)
    }

    @Test("Setup events do not reset the quiet window")
    func setupEventsAreIgnored() async {
        let bridge = CloudKitEventBridge()
        let monitor = SyncQuiesceMonitor(bridge: bridge)
        let churner = Task { [bridge] in
            for _ in 0..<5 {
                await bridge.recordEvent(CloudKitSyncEvent(type: .setup, started: false, endedAt: Date(), error: nil))
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        defer { churner.cancel() }
        let result = await monitor.waitForQuiesce(minQuietWindow: 0.3, hardTimeout: 2)
        #expect(result == .quiesced)
    }
}
