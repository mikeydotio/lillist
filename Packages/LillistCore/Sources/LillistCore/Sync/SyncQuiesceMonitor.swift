import Foundation

/// Outcome of `SyncQuiesceMonitor.waitForQuiesce`.
public enum QuiesceResult: Sendable, Equatable {
    /// No CloudKit events arrived for at least `minQuietWindow` and
    /// the wait returned normally.
    case quiesced
    /// `hardTimeout` elapsed before a quiet window of the requested
    /// duration was observed. The caller proceeds anyway and surfaces
    /// "still syncing in background" copy.
    case timedOut
}

/// Decides when CloudKit mirroring has "settled enough" after a
/// sync-mode change to flip the mode flag and dismiss the migration
/// progress sheet.
///
/// `NSPersistentCloudKitContainer.eventChangedNotification` does **not**
/// emit a terminal "all done" event (skeptic A4). The monitor uses a
/// quiesce heuristic instead: a watcher Task drains the event bridge
/// and updates `lastEventAt` whenever a real `.import` / `.export`
/// arrives; a polling loop returns `.quiesced` when no event has
/// arrived for at least `minQuietWindow` seconds, or `.timedOut` when
/// `hardTimeout` elapses first.
///
/// The heuristic is intentionally not bulletproof; live CloudKit
/// integration testing (Wave 7 runbook) covers the ground truth.
///
/// `data-sync-hardening` `S14` fixed two bugs in the original
/// single-`Date`-field design:
///
/// 1. **`.setup` events didn't count as activity.** A freshly-attached
///    mirror's `.setup` handshake can run for several seconds with zero
///    `.import`/`.export` traffic; the monitor could declare `.quiesced`
///    while `.setup` was still in progress. Every event type now bumps
///    the clock — `CloudKitSyncEvent.EventType` is exhaustively
///    `{setup, import, export}`, so there is no longer a type filter.
/// 2. **Concurrent waiters shared one clock.** A single `lastEventAt`
///    stored property meant waiter B's mere *entry* into
///    `waitForQuiesce` (which reset the clock to "now") could delay
///    waiter A's quiescence detection even though no real CloudKit
///    event fired. Each call now tracks its own entry in
///    `lastEventAt`, keyed by a private per-call identifier and
///    removed on exit — waiters never observe each other's state.
public actor SyncQuiesceMonitor {
    private let bridge: CloudKitEventBridge
    /// One entry per in-flight `waitForQuiesce` call. Never read or
    /// written across calls — see the type doc's point 2 above.
    private var lastEventAt: [UUID: Date] = [:]

    public init(bridge: CloudKitEventBridge) {
        self.bridge = bridge
    }

    public func waitForQuiesce(
        minQuietWindow: TimeInterval = 5,
        hardTimeout: TimeInterval = 300
    ) async -> QuiesceResult {
        let waiterID = UUID()
        let stream = await bridge.eventStream
        lastEventAt[waiterID] = Date()
        defer { lastEventAt[waiterID] = nil }

        // Watcher: pulls every event the bridge yields. Every event type
        // counts as activity (see the type doc's point 1 above) — a
        // still-in-progress `.setup` handshake must keep the window open
        // exactly like a mid-flight `.import`/`.export` does.
        let watcher = Task { [weak self] in
            for await _ in stream {
                guard let self else { break }
                await self.recordEvent(waiterID: waiterID)
            }
        }
        defer { watcher.cancel() }

        let deadline = Date().addingTimeInterval(hardTimeout)
        let pollInterval = max(0.05, min(0.5, minQuietWindow / 4))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            let elapsed = Date().timeIntervalSince(lastEventAt[waiterID] ?? Date())
            if QuiesceDecision.isQuiesced(elapsedSinceLastEvent: elapsed, minQuietWindow: minQuietWindow) {
                return .quiesced
            }
        }
        return .timedOut
    }

    private func recordEvent(waiterID: UUID) {
        lastEventAt[waiterID] = Date()
    }
}

/// The one comparison `waitForQuiesce`'s poll loop makes every tick,
/// extracted so it has a real name and can be driven directly by a test
/// (`LIL-84`). A pure, zero-behavior-change extraction — `waitForQuiesce`
/// itself is otherwise untouched, so this carries none of the risk a
/// deeper refactor (e.g. replacing the loop's own `Date()`/`hardTimeout`
/// structure) would.
///
/// `SyncQuiesceDecisionTests` drives this in a synthetic simulation loop
/// (a caller-supplied schedule of "an event arrives at tick N" instead of
/// a real `CloudKitEventBridge`) to prove the full S14 poll-loop shape —
/// an event arriving at any point resets the quiet window; a `.setup`
/// event counts exactly like `.import`/`.export`; concurrent waiters never
/// observe each other's clock — deterministically, with zero real elapsed
/// time and therefore zero wall-clock contention sensitivity. This is the
/// durable fix for `SyncQuiesceMonitorTests`' own tight (300ms/500ms)
/// real-time budgets flaking under `swift test --parallel` CPU contention;
/// those tests remain as lightweight real-clock smoke tests, no longer the
/// sole proof of correctness.
enum QuiesceDecision {
    static func isQuiesced(elapsedSinceLastEvent: TimeInterval, minQuietWindow: TimeInterval) -> Bool {
        elapsedSinceLastEvent >= minQuietWindow
    }
}
