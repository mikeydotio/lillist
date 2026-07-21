import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("CloudKitSyncStatusAdapter")
struct CloudKitSyncStatusAdapterTests {

    // MARK: - Pure mapping (SyncStatus → SyncIndicator)

    @Test("In-progress status maps to .inProgress, ignoring date/error")
    func mapsInProgress() {
        let status = SyncStatus(
            lastSyncedAt: Date(timeIntervalSince1970: 10),
            inProgress: true,
            error: .syncFailure(underlying: "boom")
        )
        #expect(CloudKitSyncStatusAdapter.indicator(for: status) == .inProgress)
    }

    @Test("Errored (settled) status maps to .error carrying the last success date")
    func mapsError() {
        let last = Date(timeIntervalSince1970: 500)
        let status = SyncStatus(lastSyncedAt: last, inProgress: false, error: .syncFailure(underlying: "nope"))
        let expected = SyncIndicator.error(
            message: LillistError.syncFailure(underlying: "nope").localizedDescription,
            lastSuccess: last
        )
        #expect(CloudKitSyncStatusAdapter.indicator(for: status) == expected)
    }

    @Test("Settled status with a timestamp maps to .idle(lastSync:)")
    func mapsIdleWithDate() {
        let ts = Date(timeIntervalSince1970: 1_000)
        let status = SyncStatus(lastSyncedAt: ts, inProgress: false, error: nil)
        #expect(CloudKitSyncStatusAdapter.indicator(for: status) == .idle(lastSync: ts))
    }

    @Test("Fresh status (no activity yet) maps to .idle(lastSync: nil)")
    func mapsIdleNil() {
        #expect(CloudKitSyncStatusAdapter.indicator(for: .idle) == .idle(lastSync: nil))
    }

    @Test("Issue #66: a stalled-export status maps to .error, keeping the last real success")
    func mapsSyncStalled() {
        let last = Date(timeIntervalSince1970: 500)
        let status = SyncStatus(lastSyncedAt: last, inProgress: false, error: .syncStalled(consecutiveFailures: 3))
        let expected = SyncIndicator.error(
            message: LillistError.syncStalled(consecutiveFailures: 3).localizedDescription,
            lastSuccess: last
        )
        #expect(CloudKitSyncStatusAdapter.indicator(for: status) == expected)
    }

    // MARK: - Observable update path

    @MainActor
    @Test("apply() publishes the mapped indicator")
    func applyUpdatesIndicator() {
        let adapter = CloudKitSyncStatusAdapter(monitor: SyncStatusMonitor(bridge: CloudKitEventBridge()))
        #expect(adapter.indicator == .idle(lastSync: nil))

        adapter.apply(SyncStatus(inProgress: true))
        #expect(adapter.indicator == .inProgress)

        let ts = Date(timeIntervalSince1970: 42)
        adapter.apply(SyncStatus(lastSyncedAt: ts, inProgress: false, error: nil))
        #expect(adapter.indicator == .idle(lastSync: ts))
    }

    // MARK: - End-to-end wiring (bridge → monitor → adapter)

    @MainActor
    @Test("start() reflects a real CloudKit export event into the indicator")
    func startReflectsBridgeEvent() async throws {
        let bridge = CloudKitEventBridge()
        let adapter = CloudKitSyncStatusAdapter(monitor: SyncStatusMonitor(bridge: bridge))
        await adapter.start()
        // start() subscribes synchronously (no pre-subscription drop race —
        // see CloudKitEventBridge.eventStream), so this event propagates.
        let ts = Date(timeIntervalSince1970: 1_234_567)
        await bridge.recordEvent(CloudKitSyncEvent(type: .export, started: false, endedAt: ts, error: nil))

        try await waitUntil { adapter.indicator == .idle(lastSync: ts) }
        #expect(adapter.indicator == .idle(lastSync: ts))

        adapter.stop()
        await bridge.detach()
    }

    /// Poll a main-actor condition until true or a bounded number of short
    /// sleeps elapse. Generous cap (~5s) so it tolerates CPU contention under
    /// parallel test runs rather than failing fast on a slow scheduler.
    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        iterations: Int = 500,
        step: Duration = .milliseconds(10)
    ) async throws {
        for _ in 0..<iterations {
            if condition() { return }
            try await Task.sleep(for: step)
        }
        #expect(condition(), "condition did not become true within the timeout")
    }
}
