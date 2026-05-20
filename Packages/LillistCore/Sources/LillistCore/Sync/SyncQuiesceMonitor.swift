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
public actor SyncQuiesceMonitor {
    private let bridge: CloudKitEventBridge
    private var lastEventAt: Date = Date()

    public init(bridge: CloudKitEventBridge) {
        self.bridge = bridge
    }

    public func waitForQuiesce(
        minQuietWindow: TimeInterval = 5,
        hardTimeout: TimeInterval = 300
    ) async -> QuiesceResult {
        let stream = await bridge.eventStream
        lastEventAt = Date()

        // Watcher: pulls every event the bridge yields, bumps the
        // last-event timestamp for the ones that matter.
        let watcher = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                if event.type == .import || event.type == .export {
                    await self.recordEvent()
                }
            }
        }
        defer { watcher.cancel() }

        let deadline = Date().addingTimeInterval(hardTimeout)
        let pollInterval = max(0.05, min(0.5, minQuietWindow / 4))
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            let elapsed = Date().timeIntervalSince(lastEventAt)
            if elapsed >= minQuietWindow {
                return .quiesced
            }
        }
        return .timedOut
    }

    private func recordEvent() {
        lastEventAt = Date()
    }
}
