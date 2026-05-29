import Foundation

/// High-level wrapper that selects which mode-change operation the
/// user kicked off.
public enum EnableDirection: Sendable, Equatable {
    /// Replace whatever is in iCloud with this device's local data.
    case replaceICloud
    /// Replace this device's local data with what's in iCloud.
    case replaceLocal
}

/// Whether disable-iCloud syncs first or disconnects immediately.
public enum DisableStrategy: Sendable, Equatable {
    case syncFirst
    case now
}

/// Orchestrates the phase sequence around a `PersistenceHost`
/// `reconfigure(to:)` call: pre-flight (cancel notifications,
/// quarantine the live store, mark the journal), the structural
/// swap, post-flight (CloudKit zone erase, sync quiesce), and on
/// failure leaves the journal `.failed` for the recovery sheet.
///
/// `MigrationPhase` events flow into `progressStream` so the iOS
/// `SyncMigrationProgressSheet` (Wave 5) can render each step.
///
/// The coordinator is `@MainActor` because callers are SwiftUI
/// views; internal phase work hops onto the embedded actors as
/// needed.
@MainActor
public final class MigrationCoordinator {
    private let host: any PersistenceReconfiguring
    private let journal: any MigrationJournalStore
    private let quarantine: QuarantineManager
    private let zoneEraser: CloudKitZoneEraser
    private let quiesceMonitor: SyncQuiesceMonitor
    private let notificationScheduler: NotificationScheduler?
    private let syncModeStore: SyncModeStore
    /// Plan 21 Wave 8.1: optional breadcrumb buffer for telemetry.
    private let breadcrumbs: BreadcrumbBuffer?
    /// CloudKit container identifier used by `zoneEraser`. Inherits
    /// from `host` at init.
    private let cloudKitContainerIdentifier: String
    /// Returns the current count of user-visible task rows in the live
    /// store. Used to precondition a non-empty local store before the
    /// irreversible `replaceICloudWithLocal` erase. Injected so the
    /// executing tests can drive empty/non-empty without a live store.
    private let localStoreRowCount: @Sendable () async -> Int

    private var progressContinuations: [UUID: AsyncStream<MigrationPhase>.Continuation] = [:]

    public init(
        host: any PersistenceReconfiguring,
        journal: any MigrationJournalStore,
        quarantine: QuarantineManager,
        zoneEraser: CloudKitZoneEraser,
        quiesceMonitor: SyncQuiesceMonitor,
        notificationScheduler: NotificationScheduler?,
        syncModeStore: SyncModeStore,
        breadcrumbs: BreadcrumbBuffer? = nil,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        localStoreRowCount: @escaping @Sendable () async -> Int = { 1 }
    ) {
        self.host = host
        self.journal = journal
        self.quarantine = quarantine
        self.zoneEraser = zoneEraser
        self.quiesceMonitor = quiesceMonitor
        self.notificationScheduler = notificationScheduler
        self.syncModeStore = syncModeStore
        self.breadcrumbs = breadcrumbs
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.localStoreRowCount = localStoreRowCount
    }

    /// Fire-and-forget breadcrumb emit. Failures are silenced
    /// (breadcrumbs are diagnostic-only).
    private func breadcrumb(_ action: String, success: Bool = true) {
        guard let buffer = breadcrumbs else { return }
        Task { try? await buffer.record(action: action, success: success) }
    }

    /// AsyncStream of phase events. Subscribed to by the progress
    /// sheet for live updates.
    public var progressStream: AsyncStream<MigrationPhase> {
        AsyncStream { continuation in
            let id = UUID()
            self.progressContinuations[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.progressContinuations[id] = nil
                }
            }
        }
    }

    private func emit(_ phase: MigrationPhase) {
        for continuation in progressContinuations.values {
            continuation.yield(phase)
        }
    }

    // MARK: - Enable (LocalOnly → iCloudSync)

    public func beginEnable(direction: EnableDirection, storeURL: URL) async throws {
        let op: ModeTransitionOp = direction == .replaceICloud ? .replaceICloudWithLocal : .replaceLocalWithICloud
        try await runMigration(op: op, targetMode: .iCloudSync, storeURL: storeURL)
    }

    // MARK: - Disable (iCloudSync → LocalOnly)

    public func beginDisable(strategy: DisableStrategy, storeURL: URL) async throws {
        let op: ModeTransitionOp = strategy == .syncFirst ? .syncFirstThenDisable : .disableNow
        try await runMigration(op: op, targetMode: .localOnly, storeURL: storeURL)
    }

    // MARK: - Recovery

    /// Read the journal on launch. If non-idle, surface the recovery
    /// path to the UI by emitting `.failed` and leaving the journal
    /// intact. The actual recovery (restore from backup, retry)
    /// is driven by user choice.
    public func resumeOrRecover() async throws -> MigrationJournal {
        let current = try journal.read()
        if current.isInFlight {
            emit(.failed(reason: current.failureReason ?? "Migration interrupted"))
        }
        return current
    }

    /// Restore from the quarantine backup the journal recorded and
    /// revert `syncMode` to whatever was active before the failed
    /// migration. Clears the journal on success.
    ///
    /// Resolution order (sync-7): prefer the *exact* folder the journal
    /// recorded in `quarantineFolderName` (written by `runMigration`'s
    /// copy step) so recovery restores the precise archive tied to this
    /// migration, not a guess. Legacy journals (and any whose recorded
    /// folder no longer resolves on disk) fall back to the most-recent
    /// quarantined store. If neither resolves, surface
    /// `storeUnavailable`.
    public func restoreFromBackup(filename: String = "Lillist.sqlite", targetURL: URL) async throws {
        let entry = try journal.read()
        let recorded: URL? = try entry.quarantineFolderName.flatMap {
            try quarantine.quarantinedStore(folderName: $0, filename: filename)
        }
        let backup = try recorded ?? quarantine.latestQuarantinedStore(filename: filename)
        guard let backup else {
            throw LillistError.storeUnavailable(reason: "No quarantine backup available")
        }
        emit(.removingLocalStore)
        try quarantine.restore(quarantinedStore: backup, to: targetURL)
        let prev = entry.previousMode ?? .localOnly
        await syncModeStore.setMode(prev)
        try await host.reconfigure(to: prev)
        try journal.clear()
        emit(.completed)
    }

    // MARK: - Core migration runner

    private func runMigration(op: ModeTransitionOp, targetMode: SyncMode, storeURL: URL) async throws {
        breadcrumb("sync mode change start \(op.rawValue)")
        // 1. preparing — cancel notifications first so a destructive
        //    op doesn't leave stale fires pointing at deleted rows
        //    (skeptic G9). cancelAllPending MUST precede any
        //    destructive step.
        emit(.preparing)
        if let scheduler = notificationScheduler {
            await scheduler.cancelAllPending()
        }

        // 2. journal: starting
        var entry = MigrationJournal(
            state: .preparing,
            operation: op,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            previousMode: await host.currentMode
        )
        try journal.write(entry)

        do {
            // 3. precondition: an irreversible erase must not run
            //    against an empty local store (sync-7). If the user has
            //    no local data, "replace iCloud with local" would wipe
            //    iCloud and leave them with nothing.
            if op == .replaceICloudWithLocal {
                let rows = await localStoreRowCount()
                guard rows > 0 else {
                    throw LillistError.storeUnavailable(
                        reason: "Refusing to replace iCloud with an empty local store"
                    )
                }
            }

            // 4. structural swap FIRST so the SQLite connection to the
            //    old file is closed before we touch the file on disk
            //    (persist-3). PersistenceHost.reconfigure removes the
            //    old store from the coordinator (closing the
            //    connection) and re-adds a fresh description; the old
            //    on-disk file is left intact for the copy below.
            entry.state = .reconfiguringStore
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.reconfiguringStore)
            try await host.reconfigure(to: targetMode)
            await syncModeStore.setMode(targetMode)

            // 5. quarantine the now-closed old store as a recovery
            //    anchor — COPY, not move, and only if the file is still
            //    present. Record the exact folder name in the journal.
            emit(.backingUp)
            entry.state = .quarantining
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let backup = try quarantine.copyStore(at: storeURL)
                entry.quarantineFolderName = backup.folderName
                try journal.write(entry)
            }

            // 6. cloudkit-side mutation (only for replaceICloudWithLocal).
            if op == .replaceICloudWithLocal {
                entry.state = .mutatingCloudKit
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.erasingICloud(progress: 0))
                _ = try await zoneEraser.eraseManagedZones(
                    in: cloudKitContainerIdentifier,
                    progress: { [weak self] fraction in
                        await MainActor.run { self?.emit(.erasingICloud(progress: fraction)) }
                    }
                )
            }

            // 7. wait for CloudKit to settle (only when going to
            //    iCloudSync; LocalOnly has nothing to wait on).
            if targetMode == .iCloudSync {
                entry.state = .awaitingSync
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(op == .replaceICloudWithLocal ? .uploading(progress: nil) : .downloading(progress: nil))
                _ = await quiesceMonitor.waitForQuiesce(minQuietWindow: 5, hardTimeout: 300)
            }

            // 8. finalize.
            entry.state = .finalizing
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.finalizing)

            try journal.clear()
            emit(.completed)
            breadcrumb("sync mode change completed \(op.rawValue)")
        } catch {
            entry.state = .failed
            entry.failureReason = "\(error)"
            entry.lastHeartbeatAt = Date()
            try? journal.write(entry)
            emit(.failed(reason: "\(error)"))
            breadcrumb("sync mode change failed \(op.rawValue)", success: false)
            throw error
        }
    }
}
