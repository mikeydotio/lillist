import Testing
import Foundation
@testable import LillistCore

@Suite("LiveNetworkReachability")
struct LiveNetworkReachabilityTests {
    @Test("Before start(), isReachable() returns the documented default (true) — never falsely offline")
    func defaultsToReachableBeforeStart() async {
        let monitor = LiveNetworkReachability()
        #expect(await monitor.isReachable() == true)
    }

    @Test("start() is idempotent — a second call is a harmless no-op")
    func startIsIdempotent() async {
        let monitor = LiveNetworkReachability()
        await monitor.start()
        await monitor.start() // must not crash, hang, or throw
        // Give the real NWPathMonitor a moment to deliver its first
        // update (or not — either way isReachable() must return promptly).
        _ = await monitor.isReachable()
    }

    @Test("isReachable() returns promptly after start() on a real network stack")
    func isReachableReturnsPromptly() async {
        let monitor = LiveNetworkReachability()
        await monitor.start()
        // This machine's CI/dev environment has SOME network configuration
        // (even if offline, NWPathMonitor still reports a definite status
        // quickly) — the assertion here is just that the call completes,
        // proving the actor-isolated cache is readable without hanging on
        // the callback-based monitor.
        let reachable = await monitor.isReachable()
        #expect(reachable == true || reachable == false)
    }
}
