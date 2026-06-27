import Foundation

/// Aggregates a stream of `CloudKitSyncEvent`s into a published `SyncStatus`
/// (design Sections 3 and 8). Driven by `CloudKitEventBridge`.
public actor SyncStatusMonitor {
    public private(set) var currentStatus: SyncStatus = .idle

    private let bridge: CloudKitEventBridge
    private var consumeTask: Task<Void, Never>?
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    public init(bridge: CloudKitEventBridge) {
        self.bridge = bridge
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
            if let err = event.error {
                if event.recoverable {
                    // Transient (network / a record conflict the mirror reconciles
                    // / back-off): do NOT latch a persistent red error for a one-off
                    // export blip. Keep the prior lastSyncedAt so the indicator
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
}
