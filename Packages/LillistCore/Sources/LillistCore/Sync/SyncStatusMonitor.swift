import Foundation

/// Aggregates a stream of `CloudKitSyncEvent`s into a published `SyncStatus`
/// (design Sections 3 and 8). Driven by `CloudKitEventBridge`.
public actor SyncStatusMonitor {
    public private(set) var currentStatus: SyncStatus = .idle

    /// Issue #66: consecutive **recoverable** export failures since the last
    /// successful export, with no successful export in between. Resets to 0
    /// on any successful export or any *structural* failure (which already
    /// surfaces on its own — see `apply(_:)`). Exposed so
    /// `SyncDiagnosticsSnapshot` can capture it without SQLite forensics.
    public private(set) var consecutiveExportFailures: Int = 0

    /// Recoverable export failures in a row before the streak escalates to a
    /// surfaced (red) `.syncStalled` error. `CloudKitErrorClassifier`
    /// deliberately treats a *single* bare `partialFailure` as recoverable so
    /// a one-off blip doesn't latch a permanent red badge (see its doc); this
    /// threshold is what tells a one-off blip apart from a genuinely wedged
    /// export — issue #66 found devices stuck for weeks with every local
    /// change silently failing to upload while the badge stayed calm.
    private let stallThreshold: Int

    private let bridge: CloudKitEventBridge
    private var consumeTask: Task<Void, Never>?
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    public init(bridge: CloudKitEventBridge, stallThreshold: Int = 3) {
        self.bridge = bridge
        self.stallThreshold = stallThreshold
    }

    /// Cancel the consumer task. The `[weak self]` capture makes this
    /// optional in production but lets tests halt the monitor deterministically.
    public func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// Begin consuming events from the bridge. Idempotent — calling more
    /// than once leaves the existing consumer running.
    public func start() async {
        guard consumeTask == nil else { return }
        let stream = await bridge.eventStream
        consumeTask = Task { [weak self] in
            for await event in stream {
                await self?.apply(event)
            }
        }
    }

    public var statusStream: AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let id = UUID()
            // Synchronous same-actor registration — see CloudKitEventBridge.eventStream
            // for the full rationale. The onTermination closure below is
            // @Sendable and crosses isolation, so its Task with `await`
            // is genuine.
            self.registerStatus(id: id, continuation: continuation)
            continuation.onTermination = { _ in
                Task { await self.unregisterStatus(id: id) }
            }
        }
    }

    private func registerStatus(id: UUID, continuation: AsyncStream<SyncStatus>.Continuation) {
        statusContinuations[id] = continuation
        continuation.yield(currentStatus)
    }

    private func unregisterStatus(id: UUID) {
        statusContinuations[id] = nil
    }

    private func apply(_ event: CloudKitSyncEvent) {
        var next = currentStatus
        if event.started {
            next.inProgress = true
            next.error = nil
        } else {
            next.inProgress = false
            if event.type == .export {
                applyExportOutcome(event, into: &next)
            } else if let err = event.error {
                if event.recoverable {
                    // Transient (network / a record conflict the mirror reconciles
                    // / back-off): do NOT latch a persistent red error for a one-off
                    // blip. Keep the prior lastSyncedAt so the indicator
                    // stays calm; a genuinely structural failure still surfaces.
                    next.error = nil
                } else {
                    next.error = err
                }
            } else if let endedAt = event.endedAt {
                next.lastSyncedAt = endedAt
                next.error = nil
            }
        }
        currentStatus = next
        for continuation in statusContinuations.values {
            continuation.yield(next)
        }
    }

    /// Export-specific outcome handling. Layers `consecutiveExportFailures`
    /// tracking on top of the general recoverable/structural split above: a
    /// *single* recoverable export failure still doesn't latch a red error
    /// (issue #54's fix stands), but a streak reaching `stallThreshold` does
    /// (issue #66) — that's the difference between a one-off blip and an
    /// export that has actually stopped working.
    private func applyExportOutcome(_ event: CloudKitSyncEvent, into next: inout SyncStatus) {
        guard let err = event.error else {
            consecutiveExportFailures = 0
            if let endedAt = event.endedAt {
                next.lastSyncedAt = endedAt
            }
            next.error = nil
            return
        }
        guard event.recoverable else {
            // Structural failures (quota, auth, rejected, …) already surface
            // on their own; the recoverable-only streak doesn't apply.
            consecutiveExportFailures = 0
            next.error = err
            return
        }
        consecutiveExportFailures += 1
        if consecutiveExportFailures >= stallThreshold {
            next.error = .syncStalled(consecutiveFailures: consecutiveExportFailures)
        } else {
            next.error = nil
        }
    }
}
