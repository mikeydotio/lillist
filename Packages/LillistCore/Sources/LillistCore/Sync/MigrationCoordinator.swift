import Foundation
import os

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
/// Closure that reports the current iCloud account state. Injected so
/// `MigrationCoordinator` can refuse a destructive erase when the
/// account changed out from under us without depending on `CloudKit`
/// directly (keeps the type unit-testable). Returns `nil` to mean
/// "unknown — proceed" (the conservative default keeps current behavior).
public typealias AccountStateProviding = @Sendable () async -> iCloudAccountState?

@MainActor
public final class MigrationCoordinator {
    /// Widened to `& PersistenceResetting` (S1): `replaceLocalWithICloud`
    /// now tears down and rebuilds the local store empty before
    /// re-attaching mirroring, reusing the same primitives
    /// `DataStoreResetService` uses for a destructive reset. Both
    /// production conformers (`PersistenceHost`) and the test fake
    /// (`FakePersistenceReconfigurer`) already satisfy both protocols.
    private let host: any PersistenceReconfiguring & PersistenceResetting
    private let journal: any MigrationJournalStore
    private let quarantine: QuarantineManager
    private let zoneEraser: CloudKitZoneEraser
    private let quiesceMonitor: SyncQuiesceMonitor
    private let notificationScheduler: NotificationScheduler?
    /// Optional source of the persisted morning-summary preference, read
    /// during `.finalizing` so the post-migration restore re-derives the
    /// morning summary from durable state rather than guessing.
    private let preferencesStore: PreferencesStore?
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
    /// Optional account-identity probe consulted before the irreversible
    /// CloudKit zone erase. `nil` → no pre-flight (legacy behavior).
    private let accountStateProvider: AccountStateProviding?
    /// Shared lock serializing this coordinator against
    /// `DataStoreResetService` (and `restoreFromBackup`, below) — both
    /// mutate the same `PersistenceHost` and must never run concurrently
    /// (`S11`). Defaults to a private instance so every existing
    /// single-type test is unaffected; `AppEnvironment` constructs ONE
    /// instance and injects it into both types to close the cross-type
    /// window in production. Replaces the prior type-local `isMigrating`
    /// boolean, which only ever closed this type's *own* reentrancy
    /// window.
    private let destructiveOpGate: DestructiveOpGate
    /// `waitForQuiesce`'s quiet-window/hard-timeout pair. Production
    /// default matches the pre-existing hardcoded values (5s / 300s —
    /// `MigrationJournal.staleThreshold`'s doc comment is written against
    /// this 300s ceiling, so don't change the default without revisiting
    /// that too). Injectable so tests can exercise the `.timedOut` branch
    /// (S5/S14) deterministically in milliseconds instead of waiting 300
    /// real seconds.
    private let quiesceMinQuietWindow: TimeInterval
    private let quiesceHardTimeout: TimeInterval
    /// `S21`: clears `SyncStatusMonitor`'s stall counters/forensics after a
    /// successful reconfigure or restore — nothing previously told the
    /// monitor "the store just changed, whatever streak it was tracking no
    /// longer applies." Called only on success (never on failure — a
    /// failed op hasn't actually changed the store's sync health). `nil`
    /// preserves prior behavior for every existing test/legacy caller.
    private let syncStatusReset: (@Sendable () async -> Void)?
    /// Data-sync-hardening `X11`: clears every persistent-history
    /// watermark after a destroy/rebuild — see `WatermarkRegistry`'s own
    /// doc comment. Called only for `.replaceLocalWithICloud`, the one
    /// migration op that actually destroys/rebuilds the local store (the
    /// other three tear down and reattach the *same* file, so their
    /// watermarks stay valid). Not `@Sendable`: this type is already
    /// `@MainActor`-isolated.
    private let historyWatermarksReset: (() async -> Void)?
    /// Data-sync-hardening `X11`: clears + regenerates the widget snapshot
    /// cache and reloads timelines. Same `.replaceLocalWithICloud`-only
    /// gating as `historyWatermarksReset` — see that property's doc
    /// comment.
    private let widgetCacheReset: (() async -> Void)?
    /// Data-sync-hardening `S19`: reports whether the CloudKit zone this
    /// account mirrors to currently has any records. Consulted only before
    /// `.replaceLocalWithICloud`'s irreversible local wipe — the symmetric
    /// counterpart to `localStoreRowCount`'s guard on
    /// `.replaceICloudWithLocal` (never erase iCloud for an empty local
    /// store; never wipe local data to download an empty iCloud). `nil` →
    /// no pre-flight (legacy/test behavior, matching every other optional
    /// guard's default).
    private let remoteZoneHasRecords: (@Sendable () async throws -> Bool)?
    /// `LIL-80`: resyncs the live JSON backup package after
    /// `restoreFromBackup`'s raw-SQLite file swap — a DIFFERENT subsystem
    /// from `BackupRestoreService`'s JSON-package restore (which `2b`'s
    /// `S23` fix already covers via this same protocol), but with the
    /// identical gap: swapping the store file directly triggers no Core
    /// Data save, so `LocalBackupCoordinator`'s observers never fire and
    /// the live backup package is left describing the pre-restore store.
    /// Called only on `restoreFromBackup`'s successful-completion path, the
    /// same "only on success" discipline every other reset-adjacent closure
    /// on this type follows. `nil` preserves prior behavior for tests/legacy
    /// callers.
    private let backupReconciler: (any BackupPackageReconciling)?

    private var progressContinuations: [UUID: AsyncStream<MigrationPhase>.Continuation] = [:]

    public init(
        host: any PersistenceReconfiguring & PersistenceResetting,
        journal: any MigrationJournalStore,
        quarantine: QuarantineManager,
        zoneEraser: CloudKitZoneEraser,
        quiesceMonitor: SyncQuiesceMonitor,
        notificationScheduler: NotificationScheduler?,
        preferencesStore: PreferencesStore? = nil,
        syncModeStore: SyncModeStore,
        breadcrumbs: BreadcrumbBuffer? = nil,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        localStoreRowCount: @escaping @Sendable () async -> Int = { 1 },
        accountStateProvider: AccountStateProviding? = nil,
        destructiveOpGate: DestructiveOpGate = DestructiveOpGate(),
        quiesceMinQuietWindow: TimeInterval = 5,
        quiesceHardTimeout: TimeInterval = 300,
        syncStatusReset: (@Sendable () async -> Void)? = nil,
        historyWatermarksReset: (() async -> Void)? = nil,
        widgetCacheReset: (() async -> Void)? = nil,
        remoteZoneHasRecords: (@Sendable () async throws -> Bool)? = nil,
        backupReconciler: (any BackupPackageReconciling)? = nil
    ) {
        self.host = host
        self.journal = journal
        self.quarantine = quarantine
        self.zoneEraser = zoneEraser
        self.quiesceMonitor = quiesceMonitor
        self.notificationScheduler = notificationScheduler
        self.preferencesStore = preferencesStore
        self.syncModeStore = syncModeStore
        self.breadcrumbs = breadcrumbs
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.localStoreRowCount = localStoreRowCount
        self.accountStateProvider = accountStateProvider
        self.destructiveOpGate = destructiveOpGate
        self.quiesceMinQuietWindow = quiesceMinQuietWindow
        self.quiesceHardTimeout = quiesceHardTimeout
        self.syncStatusReset = syncStatusReset
        self.historyWatermarksReset = historyWatermarksReset
        self.widgetCacheReset = widgetCacheReset
        self.remoteZoneHasRecords = remoteZoneHasRecords
        self.backupReconciler = backupReconciler
    }

    /// Breadcrumb emit, awaited inline so phase crumbs land in
    /// operation order (not via a detached Task that could reorder
    /// start/completed/failed). Failures are silenced — breadcrumbs
    /// are diagnostic-only.
    private func breadcrumb(_ action: String, success: Bool = true) async {
        guard let buffer = breadcrumbs else { return }
        try? await buffer.record(action: action, success: success)
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

    /// Data-sync-hardening `S19`: actually re-runs the operation a failed
    /// `MigrationJournal` recorded, from the top. Traced against the
    /// recovery sheet's actual "Try Again" wiring: it previously only
    /// called `migrationJournalStore.clear()` and dismissed — a partial
    /// zone erase (or any other partially-completed step) was left exactly
    /// as the failure's `catch` block left it, with no retry ever actually
    /// attempted; the user had to notice sync was still off/on and
    /// manually re-toggle it in Settings.
    ///
    /// Clears the journal first — `runMigration`'s reentrancy guard treats
    /// any non-idle state (including `.failed`) as "already in progress"
    /// and would otherwise refuse to start the very retry this method
    /// exists to perform — then dispatches back through `beginEnable`/
    /// `beginDisable` so `runMigration` re-attempts every step from
    /// `.preparing`, including a previously-partial erase (re-erasing an
    /// already-empty zone is a safe no-op query).
    ///
    /// Throws if the journal has no recorded `operation` (shouldn't happen
    /// for a journal `resumeOrRecover()` found in-flight, but a corrupt or
    /// hand-edited journal must fail loud, not silently no-op).
    public func retryFailedOperation(from failed: MigrationJournal, storeURL: URL) async throws {
        guard let op = failed.operation else {
            throw LillistError.storeUnavailable(
                reason: "The interrupted sync change has no recorded operation to retry."
            )
        }
        try? journal.clear()
        switch op {
        case .replaceICloudWithLocal:
            try await beginEnable(direction: .replaceICloud, storeURL: storeURL)
        case .replaceLocalWithICloud:
            try await beginEnable(direction: .replaceLocal, storeURL: storeURL)
        case .syncFirstThenDisable:
            try await beginDisable(strategy: .syncFirst, storeURL: storeURL)
        case .disableNow:
            try await beginDisable(strategy: .now, storeURL: storeURL)
        }
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
        // Shares the same destructive-op lock as runMigration (S11): a
        // restore mutates files and calls host.reconfigure, and must not
        // interleave with a fresh migration or a reset either.
        try destructiveOpGate.acquire(for: .restore)
        defer { destructiveOpGate.release() }
        let entry = try journal.read()
        let recorded: URL? = try entry.quarantineFolderName.flatMap {
            try quarantine.quarantinedStore(folderName: $0, filename: filename)
        }
        let backup = try recorded ?? quarantine.latestQuarantinedStore(filename: filename)
        guard let backup else {
            LillistLog.sync.error("restoreFromBackup found no quarantine backup")
            throw LillistError.storeUnavailable(reason: "No quarantine backup available")
        }
        LillistLog.sync.notice("restoreFromBackup restoring quarantined store")
        emit(.removingLocalStore)
        let prev = entry.previousMode ?? .localOnly
        do {
            // S2: close the live store's connection BEFORE touching any
            // file on disk. The prior implementation moved the live file
            // out from under an OPEN coordinator and only reconfigured
            // afterwards — a crash (or even just `prev == currentMode`,
            // which makes `reconfigure(to:)` a silent same-mode no-op)
            // left the app writing into an unlinked/quarantined inode
            // while the journal and mode store both already claimed
            // success. No backup is requested here (`backupVia: nil`) —
            // `quarantine.restore` below already quarantines whatever is
            // currently at `targetURL` before copying the recovery
            // backup in.
            _ = try await host.tearDownStore(backupVia: nil)
            try quarantine.restore(quarantinedStore: backup, to: targetURL)
            emit(.reconfiguringStore)
            // `LIL-81`: mirrors `runMigration`'s account-changed pre-flight
            // (`.replaceICloudWithLocal`/`.replaceLocalWithICloud`) — never
            // reattach with mirroring armed against an account that
            // changed since the crash this recovers from. Gated to
            // `prev == .iCloudSync` since a `.localOnly` reattach arms no
            // mirroring regardless (matching `remoteZoneHasRecords`'s own
            // op-specific gating above). Placed after the recovery anchor
            // (`quarantine.restore` already ran) but before the one
            // irreversible-in-context step left: reattaching with
            // whatever `armsCloudKitMirroring` this host was constructed
            // with.
            if prev == .iCloudSync,
               let provider = accountStateProvider,
               await provider() == .accountChanged {
                throw LillistError.storeUnavailable(
                    reason: "iCloud account changed; aborting restore before reattaching."
                )
            }
            // Forced attach, not `reconfigure(to:)`: the file at
            // `targetURL` was just replaced out from under the
            // coordinator, so even a same-mode restore
            // (`prev == currentMode`) must open a fresh connection —
            // `reconfigure`'s same-mode guard would otherwise no-op and
            // leave the coordinator permanently detached.
            try await host.attachStore(at: prev)
        } catch {
            // Best-effort reattach so a failure at any point in this
            // sequence never leaves the coordinator permanently
            // store-less (mirrors S12's reattach-on-failure pattern).
            // The journal is deliberately left untouched here — it's
            // already `.failed` from the migration this is recovering,
            // and the recovery sheet should still offer another attempt.
            try? await host.reattachStore()
            throw error
        }
        // S8-pattern: flip the mode store only AFTER the destructive
        // file-swap and reattach both succeeded — never before. (This
        // mirrors runMigration's own S8 fix; restoreFromBackup had the
        // identical ordering bug in its own right, fixed here as part of
        // the same method rewrite.)
        await syncModeStore.setMode(prev)
        try journal.clear()
        await syncStatusReset?()
        // `LIL-80`: the file swap above triggered no Core Data save, so
        // `LocalBackupCoordinator`'s observers never saw it — resync the
        // live JSON backup package to the just-restored store explicitly,
        // the same "only on success" call every other destructive op on
        // this type makes.
        await backupReconciler?.reconcileFull()
        emit(.completed)
        LillistLog.sync.notice("restoreFromBackup completed mode=\(prev.rawValue, privacy: .public)")
    }

    // MARK: - Core migration runner

    private func runMigration(op: ModeTransitionOp, targetMode: SyncMode, storeURL: URL) async throws {
        // Reentrancy guard: although @MainActor serializes execution,
        // runMigration suspends at every `await`, so a second begin* call
        // can interleave and clobber the in-flight journal entry. Reject
        // any new migration while one is already recorded as in flight.
        // Read synchronously *before* the first suspension so the check
        // can't race itself. Leaves the existing journal untouched.
        //
        // A decode failure is NOT the same as "no journal" (S15):
        // `FileMigrationJournalStore.read()` already returns `.idle`
        // without throwing when the file is simply absent, so reaching
        // this `catch` means the file exists but failed to parse — fail
        // closed rather than silently proceeding on top of unknown state.
        let current: MigrationJournal
        do {
            current = try journal.read()
        } catch {
            throw LillistError.storeUnavailable(
                reason: "The sync migration journal is unreadable; refusing to start a new migration until it's resolved. (\(error))"
            )
        }
        if current.isInFlight {
            throw LillistError.storeUnavailable(
                reason: "A sync-mode migration is already in progress."
            )
        }
        // Shared destructive-op lock (S11): closes both this type's own
        // reentrancy window AND the cross-type window against
        // `DataStoreResetService`/`restoreFromBackup`. Synchronous — set
        // before any suspension; released on every exit path via defer.
        try destructiveOpGate.acquire(for: .migration(op))
        defer { destructiveOpGate.release() }
        let signpostID = LillistLog.signposter.makeSignpostID()
        let interval = LillistLog.signposter.beginInterval(
            "migration", id: signpostID,
            "op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )
        defer { LillistLog.signposter.endInterval("migration", interval) }
        LillistLog.sync.notice(
            "migration start op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )
        await breadcrumb("sync mode change start \(op.rawValue)")
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
                    throw LillistError.localDataEmpty
                }
            }

            // 3b. syncFirstThenDisable (S5): wait for the final export to
            //     drain BEFORE detaching mirroring — waiting AFTER
            //     reconfigure(to: .localOnly) is pointless (no CloudKit
            //     container remains to export through) and is exactly the
            //     bug this finding reports ("sync one final time first"
            //     never actually synced). Nothing destructive has
            //     happened yet, so a `.timedOut` result here FAILS the
            //     step closed (S14) rather than proceeding to strand
            //     unsynced edits.
            if op == .syncFirstThenDisable {
                entry.state = .awaitingSync
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.uploading(progress: nil))
                LillistLog.sync.notice("migration awaiting final sync before disable")
                let result = await quiesceMonitor.waitForQuiesce(minQuietWindow: quiesceMinQuietWindow, hardTimeout: quiesceHardTimeout)
                if result == .timedOut {
                    throw LillistError.syncFailure(
                        underlying: "Timed out waiting for the final sync to iCloud to complete before disconnecting."
                    )
                }
            }

            // 4. recovery anchor + destructive work, in an order specific
            //    to each op (S1, S6).
            switch op {
            case .replaceLocalWithICloud:
                // S1: this device's local data must actually be replaced,
                // not merged. Tear down -> quarantine the PRE-WIPE store
                // (the recovery anchor) -> destroy + rebuild empty ->
                // THEN reconfigure, so mirroring only ever sees a fresh,
                // empty store to download iCloud's copy into. Reuses the
                // same primitives DataStoreResetService.performReset uses.
                entry.state = .quarantining
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.backingUp)
                let backup = try await host.tearDownStore(backupVia: quarantine)
                if let backup {
                    entry.quarantineFolderName = backup.folderName
                    try journal.write(entry)
                }
                // S3: never wipe local data to download an account's copy
                // if the signed-in account changed out from under us —
                // mirrors .replaceICloudWithLocal's identical pre-flight
                // below, placed at the same relative position (after the
                // recovery-anchor backup, before the irreversible step).
                // This branch previously had no such guard at all: a user
                // could flip "iCloud Sync" on in Settings while an
                // unresolved account mismatch was active and wipe their
                // local data to redownload the WRONG account's copy.
                if let provider = accountStateProvider,
                   await provider() == .accountChanged {
                    throw LillistError.storeUnavailable(
                        reason: "iCloud account changed; aborting before wiping local data."
                    )
                }
                // S19: the symmetric guard to .replaceICloudWithLocal's
                // localStoreRowCount precondition above — never wipe real
                // local data to download from an iCloud zone that turns
                // out to have nothing in it.
                if let remoteZoneHasRecords {
                    let hasRecords = (try? await remoteZoneHasRecords()) ?? true
                    guard hasRecords else {
                        throw LillistError.iCloudDataEmpty
                    }
                }
                emit(.removingLocalStore)
                LillistLog.sync.notice("migration removing local store")
                try await host.rebuildEmptyStore()
                entry.state = .reconfiguringStore
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.reconfiguringStore)
                LillistLog.sync.notice("migration reconfiguring store")
                try await host.reconfigure(to: targetMode)

            case .replaceICloudWithLocal:
                // S6: erase the iCloud zone BEFORE mirroring re-attaches.
                // At this point the store is still plain .localOnly — no
                // mirroring delegate exists yet to race the erase, or to
                // mark local rows as already-exported ahead of it.
                //
                // S7: the quarantine anchor now comes from a CLOSED store.
                // tearDownStore closes the SQLite connection before
                // copying — the same closed-store mechanism
                // .replaceLocalWithICloud already used (via
                // host.tearDownStore above), reconciling the asymmetry
                // 2a's closing report flagged: this op used to call
                // quarantine.copyStore(at:) directly against the
                // still-open, potentially WAL-active store. The
                // disk-space pre-flight (inside tearDownStore's copy)
                // still throws before the irreversible erase below
                // (blind-spot #5) — unchanged guarantee.
                entry.state = .quarantining
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.backingUp)
                let icloudBackup = try await host.tearDownStore(backupVia: quarantine)
                if let icloudBackup {
                    entry.quarantineFolderName = icloudBackup.folderName
                    try journal.write(entry)
                }
                // Pre-flight: never erase if the signed-in account changed
                // out from under us — that would wipe the wrong account's
                // zone. This throws into the catch below, which records
                // `.failed` for the recovery sheet (PauseReason.accountChanged).
                // The store is intentionally left detached here — the
                // catch's unconditional reattach handles it.
                if let provider = accountStateProvider,
                   await provider() == .accountChanged {
                    throw LillistError.storeUnavailable(
                        reason: "iCloud account changed; aborting before erase."
                    )
                }
                entry.state = .mutatingCloudKit
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.erasingICloud(progress: 0))
                LillistLog.sync.notice("migration erasing iCloud zones")
                _ = try await zoneEraser.eraseManagedZones(
                    in: cloudKitContainerIdentifier,
                    progress: { [weak self] fraction in
                        await MainActor.run { self?.emit(.erasingICloud(progress: fraction)) }
                    }
                )
                entry.state = .reconfiguringStore
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.reconfiguringStore)
                LillistLog.sync.notice("migration reconfiguring store")
                // S2 sibling: attachStore(at:), not reconfigure(to:) — the
                // store was fully detached above by tearDownStore, so
                // there is nothing left for reconfigure's remove-then-add
                // swap to remove; attachStore performs just the add half,
                // at the target mode.
                try await host.attachStore(at: targetMode)

            case .syncFirstThenDisable, .disableNow:
                // S7: same closed-store quarantine mechanism as
                // .replaceICloudWithLocal above — see that case's comment.
                entry.state = .quarantining
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.backingUp)
                let disableBackup = try await host.tearDownStore(backupVia: quarantine)
                if let disableBackup {
                    entry.quarantineFolderName = disableBackup.folderName
                    try journal.write(entry)
                }
                entry.state = .reconfiguringStore
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.reconfiguringStore)
                LillistLog.sync.notice("migration reconfiguring store")
                try await host.attachStore(at: targetMode)
            }

            // 5. wait for CloudKit to settle (only when going to
            //    iCloudSync; LocalOnly already waited in step 3b, or
            //    doesn't wait at all for disableNow). The destructive
            //    work above already succeeded by this point, so a
            //    `.timedOut` result (S14) is logged, not fatal — there is
            //    nothing left to revert, and the mirroring delegate keeps
            //    draining the queue in the background after this call
            //    returns (matches `QuiesceResult.timedOut`'s own
            //    documented contract).
            if targetMode == .iCloudSync {
                entry.state = .awaitingSync
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(op == .replaceICloudWithLocal ? .uploading(progress: nil) : .downloading(progress: nil))
                let result = await quiesceMonitor.waitForQuiesce(minQuietWindow: quiesceMinQuietWindow, hardTimeout: quiesceHardTimeout)
                if result == .timedOut {
                    LillistLog.sync.notice(
                        "migration quiesce timed out post-completion op=\(op.rawValue, privacy: .public) — proceeding, sync continues in background"
                    )
                    await breadcrumb("migration quiesce timed out, proceeding (still syncing in background)")
                }
            }

            // 6. finalize. S8: the sync mode advances ONLY here, after
            //    every destructive step has already succeeded — never
            //    before, and therefore never needs an explicit revert on
            //    failure (any thrown error above happens before this
            //    line, so `syncModeStore` still reads `previousMode`).
            entry.state = .finalizing
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.finalizing)
            await syncModeStore.setMode(targetMode)

            // Re-install the post-migration notification steady state:
            // surviving per-task specs are reconciled and the morning
            // summary is re-derived from the persisted preference. The OS
            // pending set was cleared in step 1; this rebuilds it against
            // the now-reconfigured store.
            if let scheduler = notificationScheduler {
                let summary = try? await preferencesStore?.read()
                await scheduler.restoreSteadyState(
                    morningSummaryEnabled: summary?.morningSummaryEnabled ?? false,
                    hour: Int(summary?.morningSummaryHour ?? 9),
                    minute: Int(summary?.morningSummaryMinute ?? 0)
                )
            }

            // X11: only .replaceLocalWithICloud actually destroys/rebuilds
            // the local store (host.rebuildEmptyStore(), above) — the
            // other three ops tear down and reattach the SAME on-disk
            // file, so their watermarks stay valid and must NOT be
            // cleared (that would force a needless full replay).
            if op == .replaceLocalWithICloud {
                await historyWatermarksReset?()
                await widgetCacheReset?()
            }
            try journal.clear()
            await syncStatusReset?()
            emit(.completed)
            LillistLog.sync.notice("migration completed op=\(op.rawValue, privacy: .public)")
            await breadcrumb("sync mode change completed \(op.rawValue)")
        } catch {
            // S12/S7: every op now tears the store off the coordinator at
            // some point before its structural swap — either to
            // destroy+rebuild it empty (.replaceLocalWithICloud), or to
            // take a closed-store quarantine copy before attaching the
            // target mode (the other three ops, since S7). Whichever
            // sub-step failed, best-effort reattach — unconditionally,
            // regardless of which op was running — so the coordinator is
            // never left store-less. reattachStore() is itself a safe
            // no-op when a store is already attached (e.g. a failure
            // AFTER attachStore already succeeded), so this is safe
            // regardless of exactly where the failure occurred. The
            // quarantine backup captured above (if it got that far)
            // remains the real recovery path for the user's data.
            try? await host.reattachStore()
            entry.state = .failed
            entry.failureReason = "\(error)"
            entry.lastHeartbeatAt = Date()
            try? journal.write(entry)
            emit(.failed(reason: "\(error)"))
            LillistLog.sync.error(
                "migration failed op=\(op.rawValue, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)"
            )
            await breadcrumb("sync mode change failed \(op.rawValue)", success: false)
            throw error
        }
    }
}
