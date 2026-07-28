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
            if elapsed >= minQuietWindow {
                return .quiesced
            }
        }
        return .timedOut
    }

    private func recordEvent(waiterID: UUID) {
        lastEventAt[waiterID] = Date()
    }
}
