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

    /// Raw `CKError` domain/code behind the most recent export failure this
    /// session (recoverable or structural) — e.g. `("CKErrorDomain", 2)` for
    /// the bare `partialFailure` that wedged two #66 devices. Unlike
    /// `consecutiveExportFailures`, these persist across a later successful
    /// export: they're forensic history ("this device did hit this error at
    /// some point"), not current health.
    public private(set) var lastExportErrorDomain: String?
    public private(set) var lastExportErrorCode: Int?

    /// Issue #66: the export-stall signals bundled into one actor-isolated
    /// read, so a diagnostics capture can't observe an inconsistent partial
    /// update — three separate `await`s would each cross a suspension point
    /// where a live CloudKit event could mutate state in between.
    public struct ExportHealth: Sendable, Equatable {
        public let consecutiveFailures: Int
        public let lastErrorDomain: String?
        public let lastErrorCode: Int?

        public init(consecutiveFailures: Int, lastErrorDomain: String?, lastErrorCode: Int?) {
            self.consecutiveFailures = consecutiveFailures
            self.lastErrorDomain = lastErrorDomain
            self.lastErrorCode = lastErrorCode
        }
    }

    public var exportHealth: ExportHealth {
        ExportHealth(
            consecutiveFailures: consecutiveExportFailures,
            lastErrorDomain: lastExportErrorDomain,
            lastErrorCode: lastExportErrorCode
        )
    }

    /// `S21`: the same consecutive-recoverable-failure escalation issue #66
    /// gave the export axis, now on the import axis — a device stuck
    /// silently failing every incoming CloudKit import is just as broken
    /// as one that can't export, and the review found nothing distinguished
    /// the two before this. Mirrors `consecutiveExportFailures` exactly:
    /// resets to 0 on any successful import or any *structural* failure.
    public private(set) var consecutiveImportFailures: Int = 0
    /// Forensic history for the import axis — see
    /// `lastExportErrorDomain`/`lastExportErrorCode`'s identical doc
    /// comment.
    public private(set) var lastImportErrorDomain: String?
    public private(set) var lastImportErrorCode: Int?

    /// `S21`: import-axis mirror of `ExportHealth`. A distinct type (not a
    /// rename/merge of `ExportHealth`) — `ExportHealth` is an existing
    /// public API other call sites already depend on by name, and a
    /// generalized "SyncAxisHealth" would be a breaking rename for no
    /// behavioral gain.
    public struct ImportHealth: Sendable, Equatable {
        public let consecutiveFailures: Int
        public let lastErrorDomain: String?
        public let lastErrorCode: Int?

        public init(consecutiveFailures: Int, lastErrorDomain: String?, lastErrorCode: Int?) {
            self.consecutiveFailures = consecutiveFailures
            self.lastErrorDomain = lastErrorDomain
            self.lastErrorCode = lastErrorCode
        }
    }

    public var importHealth: ImportHealth {
        ImportHealth(
            consecutiveFailures: consecutiveImportFailures,
            lastErrorDomain: lastImportErrorDomain,
            lastErrorCode: lastImportErrorCode
        )
    }

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
            } else if event.type == .import {
                applyImportOutcome(event, into: &next)
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
        // Forensic history: record the raw error regardless of severity, and
        // regardless of whether the streak below ultimately surfaces
        // anything — a diagnostics reader benefits from "this device did hit
        // CKErrorDomain/2" even when the streak self-resolved.
        lastExportErrorDomain = event.rawErrorDomain
        lastExportErrorCode = event.rawErrorCode
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

    /// `S21`: import-axis mirror of `applyExportOutcome` — identical
    /// shape, tracking `consecutiveImportFailures` instead.
    private func applyImportOutcome(_ event: CloudKitSyncEvent, into next: inout SyncStatus) {
        guard let err = event.error else {
            consecutiveImportFailures = 0
            if let endedAt = event.endedAt {
                next.lastSyncedAt = endedAt
            }
            next.error = nil
            return
        }
        lastImportErrorDomain = event.rawErrorDomain
        lastImportErrorCode = event.rawErrorCode
        guard event.recoverable else {
            consecutiveImportFailures = 0
            next.error = err
            return
        }
        consecutiveImportFailures += 1
        if consecutiveImportFailures >= stallThreshold {
            next.error = .syncStalled(consecutiveFailures: consecutiveImportFailures)
        } else {
            next.error = nil
        }
    }

    /// `S21`: clear both axes' stall counters and forensic history — call
    /// on a successful store reconfigure/reset. Before this existed,
    /// nothing ever cleared `consecutiveExportFailures`/
    /// `consecutiveImportFailures` on a swap: a device that hit the
    /// threshold, then disabled and re-enabled sync, would start the new
    /// session already latched red, or (for a genuinely fresh store) keep
    /// reporting a stall streak that no longer has anything to do with the
    /// store now attached. See `MigrationCoordinator`/`DataStoreResetService`'s
    /// `syncStatusReset` injection point for exactly where this is called.
    public func resetStallState() {
        consecutiveExportFailures = 0
        lastExportErrorDomain = nil
        lastExportErrorCode = nil
        consecutiveImportFailures = 0
        lastImportErrorDomain = nil
        lastImportErrorCode = nil
    }
}
