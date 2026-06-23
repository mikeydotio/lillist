import Foundation
import Observation
import LillistCore

/// Bridges `LillistCore.SyncStatusMonitor` — the CloudKit-event-driven actor
/// fed by `NSPersistentCloudKitContainer.eventChangedNotification` — onto the
/// UI-facing ``SyncIndicatorMonitor`` protocol.
///
/// This replaces the ``IdleSyncIndicatorMonitor`` stub, which always reported
/// "synced just now" regardless of real activity (so two devices on *different*
/// CloudKit environments could both claim success while nothing synced). With
/// this adapter the status surface reflects genuine setup/import/export
/// progress and surfaces sync errors instead of masking them.
///
/// The snapshot→indicator translation is a pure ``indicator(for:)`` so it can
/// be unit-tested without the main actor or the async stream.
@MainActor
@Observable
public final class CloudKitSyncStatusAdapter: SyncIndicatorMonitor {
    public private(set) var indicator: SyncIndicator

    private let monitor: SyncStatusMonitor
    private var consumeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - monitor: the Core sync-status actor to observe.
    ///   - initialStatus: status reflected in ``indicator`` before ``start()``
    ///     connects the stream (defaults to `.idle`).
    public init(monitor: SyncStatusMonitor, initialStatus: SyncStatus = .idle) {
        self.monitor = monitor
        self.indicator = Self.indicator(for: initialStatus)
    }

    /// Connect to the monitor and begin reflecting live status. Idempotent — a
    /// second call while already consuming is ignored. `SyncStatusMonitor`'s
    /// `start()` kicks off the bridge consumer, and its `statusStream` yields
    /// the current status on subscribe and on every subsequent change.
    public func start() async {
        guard consumeTask == nil else { return }
        await monitor.start()
        let stream = await monitor.statusStream
        consumeTask = Task { [weak self] in
            for await status in stream {
                await MainActor.run { self?.apply(status) }
            }
        }
    }

    /// Stop consuming. Tests use this for determinism; in production the
    /// adapter lives for the lifetime of the app environment.
    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// "Sync Now" affordance. `NSPersistentCloudKitContainer` exposes no public
    /// force-sync — mirroring runs automatically on local edits and CloudKit
    /// pushes — so we re-assert the (idempotent) consumer to ensure the surface
    /// is connected, and deliberately avoid faking a success timestamp.
    public func retry() async {
        await monitor.start()
    }

    /// Reflect a status snapshot into the published ``indicator``. Internal so
    /// tests can drive the observable path without the async stream.
    func apply(_ status: SyncStatus) {
        indicator = Self.indicator(for: status)
    }

    /// Pure mapping from a Core ``SyncStatus`` snapshot to the UI
    /// ``SyncIndicator``.
    ///
    /// `.paused` is intentionally *not* produced here: the app layer overlays
    /// `pauseReason` ahead of reading this indicator (see the iOS/macOS sync
    /// settings sections), so an account-level pause wins over whatever the
    /// event stream last reported.
    public nonisolated static func indicator(for status: SyncStatus) -> SyncIndicator {
        if status.inProgress {
            return .inProgress
        }
        if let error = status.error {
            // `LillistError` is `LocalizedError`, so `localizedDescription`
            // returns its `errorDescription` — already user-facing.
            return .error(message: error.localizedDescription, lastSuccess: status.lastSyncedAt)
        }
        return .idle(lastSync: status.lastSyncedAt)
    }
}
