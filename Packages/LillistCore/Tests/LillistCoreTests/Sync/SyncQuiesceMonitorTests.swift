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

    @Test("Setup events count as activity and reset the quiet window (S14)")
    func setupEventsCountAsActivity() async {
        // Inverts the pre-fix `setupEventsAreIgnored` test, which asserted
        // the S14 bug (a still-in-progress .setup handshake read as
        // "quiesced") as correct behavior. A freshly-attached mirror can
        // emit .setup for longer than the quiet window with zero
        // .import/.export traffic; that must NOT read as settled.
        let bridge = CloudKitEventBridge()
        let monitor = SyncQuiesceMonitor(bridge: bridge)
        let churner = Task { [bridge] in
            for _ in 0..<20 {
                await bridge.recordEvent(CloudKitSyncEvent(type: .setup, started: false, endedAt: Date(), error: nil))
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        defer { churner.cancel() }
        let result = await monitor.waitForQuiesce(minQuietWindow: 0.3, hardTimeout: 0.5)
        #expect(result == .timedOut)
    }

    @Test("Concurrent waiters track independent quiet windows (S14 — no cross-talk)")
    func concurrentWaitersDoNotInterleave() async {
        let bridge = CloudKitEventBridge()
        let monitor = SyncQuiesceMonitor(bridge: bridge)

        // Waiter A: no events ever fire for it; must quiesce close to its
        // own 0.3s window, not be pushed toward its 2s hard timeout by
        // waiter B repeatedly starting/finishing unrelated waits.
        async let a: QuiesceResult = monitor.waitForQuiesce(minQuietWindow: 0.3, hardTimeout: 2.0)

        // Waiter B starts partway through A's wait and completes (exits)
        // well before A does. Under the pre-fix shared `lastEventAt`, B's
        // very *entry* into waitForQuiesce would reset A's clock even
        // though no real CloudKit event fired.
        try? await Task.sleep(nanoseconds: 100_000_000)
        let start = Date()
        let b = await monitor.waitForQuiesce(minQuietWindow: 0.05, hardTimeout: 1.0)
        #expect(b == .quiesced)

        let aResult = await a
        let elapsed = Date().timeIntervalSince(start)
        #expect(aResult == .quiesced)
        // A must resolve close to its own 0.3s window, not be stretched
        // toward its 2s timeout by B's start/finish.
        #expect(elapsed < 1.0, "waiter A took \(elapsed)s after B started — looks cross-contaminated")
    }
}
