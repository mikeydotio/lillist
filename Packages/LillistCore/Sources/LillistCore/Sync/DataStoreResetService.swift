import Foundation
import os

/// The backup-package resync primitive a destructive reset/restore needs
/// once it changes what the live store contains (`S23`). `CloudKit`
/// re-import (`LocalBackupCoordinator.processRemoteChange`) covers the
/// `.iCloudSync` case incrementally as data streams back in, but a
/// `.localOnly` wipe has no remote-change notification to trigger
/// anything — without an explicit call, the package would sit stale
/// (or, before `S4`'s fix, wrongly pruned to empty) indefinitely.
/// `LocalBackupCoordinator` is the production conformer. Not
/// `@MainActor`-isolated (unlike `BackupDataResetting`) — `reconcileFull()`
/// is a plain nonisolated `async` method, callable from the
/// `@MainActor`-isolated `DataStoreResetService`/`BackupRestoreService`
/// like any other `await`.
public protocol BackupPackageReconciling: Sendable {
    func reconcileFull() async
}

extension LocalBackupCoordinator: BackupPackageReconciling {}

/// Result of `DataStoreResetService.recoverInterruptedReseed()` (`S9b`).
public enum ReseedRecoveryOutcome: Sendable, Equatable {
    /// No reseed was in flight — a normal launch.
    case notInterrupted
    /// A reseed was interrupted before the wipe reached the live store;
    /// the original data is intact and untouched, so the stale journal
    /// entry and staged directory were simply discarded.
    case discardedSafely
    /// A reseed was interrupted after the wipe; the staged bundle was the
    /// only remaining copy and has been re-imported successfully.
    case resumed
}

/// Performs an **irreversible data-store reset** for recovering from a
/// suspected-corrupt store, or for deliberately re-converging every
/// device on this iCloud account. Four flavors, all of which back up to
/// quarantine:
///
/// - `resetAndRedownload()` ("Erase local data and download fresh")
///   destroys and rebuilds only the local store; the CloudKit zone is
///   left intact so the rebuilt store re-imports it. Local-only; never
///   propagates.
/// - `resetAllData()` — the shared "wipe local + iCloud to empty"
///   primitive `resetEverywhereToEmpty()` and `resetAndReseedFromThisDevice()`
///   are built on. Also erases the CloudKit zone when syncing. Kept
///   public because `BackupRestoreService` reuses it (via
///   `BackupDataResetting`) as the destructive half of a restore.
/// - `resetEverywhereToEmpty()` ("Erase data from all devices and start
///   over") wipes local + iCloud to empty, then propagates to every
///   other known device over `ResetPropagator` so they converge on empty
///   too — see the type doc below for why zone deletion alone (the
///   pre-issue-#71 design) does not accomplish that.
/// - `resetAndReseedFromThisDevice()` ("Erase data from all devices and
///   restore all from this device's backup") snapshots this device's
///   current data, wipes local + iCloud, re-imports the snapshot, then
///   propagates — every other device converges on *this device's* data
///   instead of empty.
///
/// ## Why propagation needed its own mechanism (issue #71)
///
/// Before this, "Reset Everywhere" propagated *only* by deleting the
/// CloudKit zone and assuming other devices would notice and wipe
/// themselves. Nothing in the stack implements that receiving-side
/// reaction: there is no `CKDatabaseSubscription`, no branch on
/// `CKError.zoneNotFound`/`.userDeletedZone`, and no remote-change
/// handler that deletes rows. A peer's local store and CloudKit
/// import-history metadata are untouched by a zone delete, so
/// `NSPersistentCloudKitContainer` simply re-creates the zone and
/// re-uploads the peer's own data — resurrecting everything. See
/// `ResetPropagator`/`ControlInbox` for the explicit, tested replacement:
/// a small out-of-band iCloud Key-Value Store signal, propagated
/// alongside (never instead of) the CloudKit wipe.
///
/// It deliberately **reuses the same hardened building blocks** as
/// `MigrationCoordinator` (quarantine backup with its disk-space
/// pre-flight, the CloudKit zone eraser, the notification cancel, the
/// sync-quiesce wait) but is a *separate* type because a reset is not a
/// sync-mode transition: the mode is unchanged, and it must **not**
/// touch the `MigrationJournal`, whose invariants (`previousMode`,
/// restore-reverts-mode) are transition-shaped. The quarantine copy is
/// the recovery anchor instead.
///
/// `@MainActor` because the caller is a SwiftUI Settings view; the
/// embedded actors are hopped onto as needed.
@MainActor
public final class DataStoreResetService {
    private let host: any PersistenceResetting
    private let quarantine: QuarantineManager
    private let zoneEraser: CloudKitZoneEraser
    private let quiesceMonitor: SyncQuiesceMonitor
    private let notificationScheduler: NotificationScheduler?
    private let cloudKitContainerIdentifier: String
    /// Optional account-identity probe consulted before the irreversible
    /// CloudKit zone erase. `nil` → no pre-flight (legacy/test behavior).
    private let accountStateProvider: AccountStateProviding?
    private let breadcrumbs: BreadcrumbBuffer?
    /// Cross-device "converge to current iCloud state" signal (issue
    /// #71). `nil` → `resetEverywhereToEmpty()`/`resetAndReseedFromThisDevice()`
    /// still wipe/reseed correctly but don't notify peers (test/legacy
    /// callers that don't exercise those two methods).
    private let propagator: ResetPropagator?
    /// Snapshot source for `resetAndReseedFromThisDevice()`. `nil` makes
    /// that method throw rather than silently reseed nothing.
    private let exporter: Exporter?
    /// Re-import target for `resetAndReseedFromThisDevice()`. `nil` makes
    /// that method throw rather than silently reseed nothing.
    private let importer: Importer?
    /// Durable crash-recovery record for `resetAndReseedFromThisDevice()`
    /// (`S9b`) — see `ReseedJournal`'s header comment for why this is a
    /// dedicated type, not a reused `MigrationJournal`. Defaults to a
    /// fresh in-memory instance (matching `destructiveOpGate`'s own
    /// default pattern) so every existing test is unaffected;
    /// `AppEnvironment` injects a real `FileReseedJournalStore` so the
    /// record survives a crash.
    private let reseedJournal: any ReseedJournalStore
    /// Resyncs the live JSON backup package after a successful destructive
    /// op (`S23`) — see `BackupPackageReconciling`'s doc comment. `nil`
    /// (the default) preserves prior behavior for tests/legacy callers.
    private let backupReconciler: (any BackupPackageReconciling)?

    /// Shared lock serializing this service against `MigrationCoordinator`
    /// (and `restoreFromBackup`) — both mutate the same `PersistenceHost`
    /// and must never run concurrently (`S11`). Defaults to a private
    /// instance so every existing single-type test is unaffected;
    /// `AppEnvironment` constructs ONE instance and injects it into both
    /// types to close the cross-type window in production. Replaces the
    /// prior type-local `isResetting` boolean, which only ever closed
    /// this type's *own* reentrancy window — every public entry point
    /// still shares one acquire via `withReentrancyGuard(label:_:)`, so a
    /// second reset while one is running still can't race the store
    /// teardown (or, for the reseed flow, its own export/reimport steps).
    private let destructiveOpGate: DestructiveOpGate
    /// `waitForQuiesce`'s quiet-window/hard-timeout pair — see
    /// `MigrationCoordinator`'s identical property for the full
    /// rationale. Injectable so tests can exercise the `.timedOut`
    /// branch (S14) in milliseconds instead of waiting 300 real seconds.
    private let quiesceMinQuietWindow: TimeInterval
    private let quiesceHardTimeout: TimeInterval
    /// `S21`: clears `SyncStatusMonitor`'s stall counters/forensics after a
    /// successful reset — see `MigrationCoordinator`'s identical property
    /// for the full rationale. Called only on success, alongside
    /// `backupReconciler?.reconcileFull()`.
    private let syncStatusReset: (@Sendable () async -> Void)?
    /// Data-sync-hardening `X11`: clears every `PersistentHistoryTokenStore`
    /// watermark after a destroy/rebuild — see `WatermarkRegistry`'s own doc
    /// comment. Called unconditionally on every successful `performReset`
    /// (every flavor destroys/rebuilds the local store). Not `@Sendable`:
    /// this type is already `@MainActor`-isolated, so the stored closure
    /// needs no Sendable-capture gymnastics. `nil` preserves prior behavior
    /// for tests/legacy callers.
    private let historyWatermarksReset: (() async -> Void)?
    /// Data-sync-hardening `X11`: clears + regenerates the widget snapshot
    /// cache and reloads timelines after a destroy/rebuild. Lives in the
    /// app layer (imports WidgetKit, which `LillistCore` never does) —
    /// this is the injection seam. Called at the same points as
    /// `historyWatermarksReset`, plus once more after
    /// `resetAndReseedFromThisDevice()`'s reimport (mirroring `S23`'s
    /// deterministic-not-incidental-timing reasoning for
    /// `backupReconciler`).
    private let widgetCacheReset: (() async -> Void)?

    public init(
        host: any PersistenceResetting,
        quarantine: QuarantineManager,
        zoneEraser: CloudKitZoneEraser,
        quiesceMonitor: SyncQuiesceMonitor,
        notificationScheduler: NotificationScheduler?,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        accountStateProvider: AccountStateProviding? = nil,
        breadcrumbs: BreadcrumbBuffer? = nil,
        propagator: ResetPropagator? = nil,
        exporter: Exporter? = nil,
        importer: Importer? = nil,
        destructiveOpGate: DestructiveOpGate = DestructiveOpGate(),
        reseedJournal: any ReseedJournalStore = InMemoryReseedJournalStore(),
        backupReconciler: (any BackupPackageReconciling)? = nil,
        quiesceMinQuietWindow: TimeInterval = 5,
        quiesceHardTimeout: TimeInterval = 300,
        syncStatusReset: (@Sendable () async -> Void)? = nil,
        historyWatermarksReset: (() async -> Void)? = nil,
        widgetCacheReset: (() async -> Void)? = nil
    ) {
        self.host = host
        self.quarantine = quarantine
        self.zoneEraser = zoneEraser
        self.quiesceMonitor = quiesceMonitor
        self.notificationScheduler = notificationScheduler
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.accountStateProvider = accountStateProvider
        self.breadcrumbs = breadcrumbs
        self.propagator = propagator
        self.exporter = exporter
        self.importer = importer
        self.destructiveOpGate = destructiveOpGate
        self.reseedJournal = reseedJournal
        self.backupReconciler = backupReconciler
        self.quiesceMinQuietWindow = quiesceMinQuietWindow
        self.quiesceHardTimeout = quiesceHardTimeout
        self.syncStatusReset = syncStatusReset
        self.historyWatermarksReset = historyWatermarksReset
        self.widgetCacheReset = widgetCacheReset
    }

    /// What a reset should do with the CloudKit side of the store.
    private enum Scope {
        /// Erase the CloudKit zone too (iCloudSync only): every device on
        /// the account loses its data. The "wipe everything" behavior.
        case everywhere
        /// Leave the CloudKit zone intact and let the freshly-rebuilt empty
        /// store re-import it. Only meaningful while syncing — there is
        /// nothing to download in local-only mode.
        case redownload
    }

    /// Wipe every task on this device **and** in iCloud, then rebuild an
    /// empty store. See `performReset` for the ordered, invariant-preserving
    /// steps. Kept public (rather than folded into `resetEverywhereToEmpty()`)
    /// because `BackupRestoreService` reuses exactly this as the destructive
    /// half of a restore, via `BackupDataResetting`.
    ///
    /// Does **not** notify other devices — see `resetEverywhereToEmpty()`,
    /// the user-facing "Erase data from all devices and start over" action,
    /// for the propagating version issue #71 added.
    public func resetAllData() async throws {
        try await withReentrancyGuard(label: "resetAllData") {
            try await performReset(.everywhere)
        }
    }

    /// Delete only this device's local copy and re-download everything from
    /// iCloud. The CloudKit zone is left untouched, so the rebuilt empty
    /// store re-imports the account's data via
    /// `NSPersistentCloudKitContainer` (which re-imports a zone whenever the
    /// local store has no import-history metadata — exactly the state a
    /// destroy+rebuild leaves it in). Use this to recover from suspected
    /// **local** corruption without losing the iCloud copy. Also the peer
    /// reaction `ResetSignalMonitor` invokes when it receives a
    /// `ResetControlEvent` — "converge to current iCloud state," regardless
    /// of which propagating action produced that state.
    ///
    /// Throws when not syncing: in local-only mode there is no CloudKit copy
    /// to download, so this would be a plain (unrecoverable-from-cloud) wipe
    /// — the caller should use `resetAllData()` if that is the intent.
    public func resetAndRedownload() async throws {
        try await withReentrancyGuard(label: "resetAndRedownload") {
            try await performReset(.redownload)
        }
    }

    /// Resolves a detected account-identity mismatch (data-sync-hardening
    /// `S3`) by wiping this device's local copy of the superseded
    /// account's data and re-downloading fresh from the now-current iCloud
    /// account. **Not** the same call path as `resetAndRedownload()` above
    /// — that method is left completely unmodified specifically so
    /// `ResetSignalMonitor`'s automatic peer-triggered reset (which calls
    /// it directly) stays unconditionally blocked by the ordinary
    /// `accountStateProvider` preflight whenever a real mismatch is
    /// active. This method is the one, narrowly-scoped, re-validating
    /// bypass: it independently re-reads the live account state itself
    /// (never trusting a stale caller-held flag) and refuses unless a
    /// mismatch is genuinely active right now, then — and only then —
    /// skips *just* `performReset`'s internal ambient throw for this one
    /// call. Every other invariant (`destructiveOpGate`, the disk
    /// pre-flight, notification cancellation, reattach-on-failure) is
    /// untouched.
    ///
    /// Callers must call `AccountIdentityStore.adoptCurrentIdentity()`
    /// **only after** this method returns successfully — never before,
    /// never on failure. See the plan doc §3's council decision for why:
    /// adopting early could let a failure-path `reattachStore()` reattach
    /// still-mismatched data with mirroring re-armed against the
    /// newly-adopted identity. A failure here always leaves the
    /// coordinator reattached (never store-less) via the same
    /// `performReset` failure handling every other reset flavor uses.
    public func resolveAccountMismatchByRedownloading() async throws {
        guard let accountStateProvider else {
            throw LillistError.storeUnavailable(reason: "Cannot resolve an account mismatch without an account-state provider configured.")
        }
        guard await accountStateProvider() == .accountChanged else {
            throw LillistError.storeUnavailable(reason: "No account mismatch is currently active to resolve.")
        }
        try await withReentrancyGuard(label: "resolveAccountMismatchByRedownloading") {
            try await performReset(.redownload, bypassAccountChangedGuard: true)
        }
    }

    /// "Erase data from all devices and start over" (issue #71). Wipes
    /// local + iCloud to empty via `resetAllData()`'s exact steps, then
    /// propagates over `ResetPropagator` so every other known device
    /// converges on empty too the next time it's open and online. Returns
    /// whether anybody was actually notified (data-sync-hardening `S20`) —
    /// `.rosterEmpty` when no `propagator` was injected or no peers are
    /// known yet, never silently treated as success.
    @discardableResult
    public func resetEverywhereToEmpty() async throws -> BroadcastOutcome {
        try await withReentrancyGuard(label: "resetEverywhereToEmpty") {
            try await performReset(.everywhere)
            return propagator?.broadcast(.resetToEmpty) ?? .notConfigured
        }
    }

    /// "Erase data from all devices and restore all from this device's
    /// backup" (issue #71). Snapshots this device's *current* data to a
    /// **durable** staging directory, wipes local + iCloud via
    /// `resetAllData()`'s exact steps, re-imports the snapshot into the
    /// freshly-emptied store, then propagates — every other known device
    /// discards its own local state and re-downloads, converging on
    /// **this device's** data (not empty) once the re-imported rows
    /// finish exporting.
    ///
    /// `S9b`: every step is journaled to `reseedJournal` and the export
    /// is staged under `quarantine.rootDirectory` (durable, App-Group-
    /// rooted) instead of `FileManager.default.temporaryDirectory`
    /// (OS-purgeable — this project's own `CLAUDE.md` documents
    /// Spotlight's `mds_stores` indexing backlog as a real trigger for
    /// exactly this kind of churn on a `$TMPDIR` directory). A crash
    /// after the wipe is recoverable via `recoverInterruptedReseed()` —
    /// see that method and `ReseedJournal`'s header comment for the
    /// recovery design. The staged directory is removed only on full
    /// success; a failure at any point leaves it (and the journal entry)
    /// in place as the recovery anchor.
    ///
    /// Throws `storeUnavailable` if constructed without an `exporter`/
    /// `importer` (both required for this flow only — every other method
    /// works without them).
    ///
    /// Data-sync-hardening `S9c`: broadcasting used to fire immediately
    /// after the reimport, with no wait for the reimported data's own
    /// re-export to CloudKit to settle — a peer that redownloaded right
    /// away could pull a **partial** zone, mid-upload. This now waits for
    /// `quiesceMonitor` (only while syncing; nothing to wait for in
    /// `.localOnly`) before broadcasting, and skips the broadcast entirely
    /// on a timeout (`.skippedQuiesceTimedOut`) rather than telling a peer
    /// to redownload a knowably-incomplete zone — the reset/reseed itself
    /// still completed successfully either way.
    @discardableResult
    public func resetAndReseedFromThisDevice() async throws -> BroadcastOutcome {
        guard let exporter, let importer else {
            throw LillistError.storeUnavailable(
                reason: "Reset & Re-seed needs the export/import subsystem, which wasn't configured."
            )
        }
        return try await withReentrancyGuard(label: "resetAndReseedFromThisDevice") {
            let stagingRoot = quarantine.rootDirectory.appendingPathComponent("Reseed", isDirectory: true)
            let stageDir = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: stageDir, withIntermediateDirectories: true)

            var entry = ReseedJournal(
                phase: .exporting,
                startedAt: Date(),
                lastHeartbeatAt: Date(),
                stagedBundlePath: stageDir.path,
                localDataWiped: false
            )
            try reseedJournal.write(entry)

            do {
                // 1. snapshot this device's current data BEFORE anything
                //    is wiped, into the durable staging directory.
                try await exporter.export(to: stageDir)

                // 2. wipe local + iCloud (same steps resetAllData() runs).
                entry.phase = .wiping
                entry.lastHeartbeatAt = Date()
                try reseedJournal.write(entry)
                try await performReset(.everywhere)
                entry.localDataWiped = true
                entry.lastHeartbeatAt = Date()
                try reseedJournal.write(entry)

                // 3. re-seed the freshly-emptied store from the staged
                //    snapshot; it re-exports to CloudKit normally from
                //    here. assetsDirectory must be passed (S9a) —
                //    Exporter.export(to:) writes attachment bytes under
                //    "<stageDir>/assets/", and the importer's
                //    attachment-restore branch is gated on this parameter
                //    being present; without it every attachment is
                //    silently dropped. Mirrors
                //    BackupRestoreService.restore(from:)'s equivalent,
                //    already-correct call (reader.assetsDirectory).
                entry.phase = .importing
                entry.lastHeartbeatAt = Date()
                try reseedJournal.write(entry)
                _ = try await importer.importBundle(
                    at: stageDir,
                    conflictPolicy: .replaceExisting,
                    assetsDirectory: stageDir.appendingPathComponent("assets", isDirectory: true)
                )
                // S23: explicit re-reconcile after the reimport — the
                // wipe's own reconcile (inside performReset, above)
                // already resynced to empty; this deterministically
                // resyncs to the reseeded content rather than relying on
                // the local-save observer's incidental timing for
                // something this important.
                await backupReconciler?.reconcileFull()
                // X11: same reasoning as S23's re-reconcile above — widgets
                // should reflect the reseeded content deterministically,
                // not "eventually" once the local-save observer notices.
                await widgetCacheReset?()

                // 4. S9c: wait for the just-reimported data's own
                //    re-export to CloudKit to settle BEFORE telling peers
                //    to redownload — only meaningful while syncing (a
                //    localOnly reseed has nothing to export or announce
                //    beyond this point). Skip the broadcast entirely on a
                //    timeout rather than pointing a peer at a knowably-
                //    partial zone; the reseed itself already succeeded
                //    locally either way.
                let outcome: BroadcastOutcome
                if await host.currentMode == .iCloudSync {
                    let result = await quiesceMonitor.waitForQuiesce(
                        minQuietWindow: quiesceMinQuietWindow, hardTimeout: quiesceHardTimeout
                    )
                    if result == .timedOut {
                        LillistLog.sync.notice("resetAndReseedFromThisDevice re-export quiesce timed out — skipping broadcast, a peer would otherwise pull a partial zone")
                        await breadcrumb("resetAndReseedFromThisDevice re-export quiesce timed out; broadcast skipped", success: false)
                        outcome = .skippedQuiesceTimedOut
                    } else {
                        outcome = propagator?.broadcast(.resetAndReseed) ?? .notConfigured
                    }
                } else {
                    outcome = propagator?.broadcast(.resetAndReseed) ?? .notConfigured
                }

                // 5. success: the staged bundle and journal entry have
                //    served their purpose — clean both up so a future
                //    launch doesn't mistake this durable-but-now-stale
                //    directory for a crashed reseed.
                try? reseedJournal.clear()
                try? FileManager.default.removeItem(at: stageDir)
                return outcome
            } catch {
                entry.phase = .failed
                entry.failureReason = "\(error)"
                entry.lastHeartbeatAt = Date()
                try? reseedJournal.write(entry)
                throw error
            }
        }
    }

    /// Detects and, when safe, resolves an interrupted
    /// `resetAndReseedFromThisDevice()` from a prior launch (`S9b`). Call
    /// once, early at launch, before any UI assumes the store reflects
    /// steady state.
    ///
    /// - If the journal is idle, this is a no-op (`.notInterrupted`).
    /// - If the wipe never reached the live store
    ///   (`localDataWiped == false`), the original data is intact and
    ///   untouched — the journal entry and the stale staged directory are
    ///   simply discarded (`.discardedSafely`).
    /// - If the wipe already ran (`localDataWiped == true`), the live
    ///   store has nothing but the staged bundle — this re-runs the
    ///   import from `stagedBundlePath` (idempotent under
    ///   `.replaceExisting`, whether or not the interrupted run got
    ///   partway through its own import) and reports `.resumed` on
    ///   success.
    @discardableResult
    public func recoverInterruptedReseed() async throws -> ReseedRecoveryOutcome {
        let entry = try reseedJournal.read()
        guard entry.isInFlight else { return .notInterrupted }

        try destructiveOpGate.acquire(for: .reset("recoverInterruptedReseed"))
        defer { destructiveOpGate.release() }

        guard entry.localDataWiped else {
            try? reseedJournal.clear()
            if let path = entry.stagedBundlePath {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
            }
            return .discardedSafely
        }
        guard let path = entry.stagedBundlePath else {
            // Shouldn't happen (localDataWiped implies the export step
            // completed and recorded a path) — surface it rather than
            // silently treating a wiped store with nothing to recover
            // from as success.
            throw LillistError.storeUnavailable(
                reason: "A reseed was interrupted after wiping local data, but its staged backup path is missing from the recovery journal."
            )
        }
        guard let importer else {
            throw LillistError.storeUnavailable(
                reason: "Can't resume the interrupted reseed: the import subsystem wasn't configured."
            )
        }
        let stageDir = URL(fileURLWithPath: path)
        _ = try await importer.importBundle(
            at: stageDir,
            conflictPolicy: .replaceExisting,
            assetsDirectory: stageDir.appendingPathComponent("assets", isDirectory: true)
        )
        // S23: resync the backup package to the just-recovered content —
        // same reasoning as the primary (non-crashed) reseed path.
        await backupReconciler?.reconcileFull()
        // X11: same reasoning — the crash-recovered reimport needs to
        // reach widgets deterministically too.
        await widgetCacheReset?()
        try? reseedJournal.clear()
        try? FileManager.default.removeItem(at: stageDir)
        return .resumed
    }

    /// Runs `operation` under the shared destructive-op gate (`S11`): a
    /// second call while one is in flight — from THIS type, from
    /// `MigrationCoordinator`, or from `restoreFromBackup` — throws
    /// immediately rather than racing the first one's store teardown (or,
    /// for the reseed flow, its own export/reimport steps). Centralized
    /// here — rather than inside `performReset` — so
    /// `resetAndReseedFromThisDevice()` can guard its *entire*
    /// export→wipe→reimport→broadcast sequence as one atomic unit, not
    /// just the inner wipe. `label` names the specific entry point for a
    /// diagnosable "already in progress" message if a blocked caller
    /// needs to know what's holding the gate.
    private func withReentrancyGuard<T>(label: String, _ operation: () async throws -> T) async throws -> T {
        try destructiveOpGate.acquire(for: .reset(label))
        defer { destructiveOpGate.release() }
        return try await operation()
    }

    /// Tear down the local store and rebuild it empty, ordered to preserve
    /// the codebase's destructive-op invariants:
    ///
    /// 1. Cancel pending notifications first, so a wipe never leaves
    ///    stale fires pointing at deleted rows (skeptic G9).
    /// 2. Account-changed pre-flight: never act on a store whose signed-in
    ///    account changed out from under us.
    /// 3. Tear down + quarantine backup — `copyStore`'s disk-space
    ///    pre-flight throws **before** the irreversible erase (blind-spot #5).
    /// 4. Erase the CloudKit zone (`.everywhere` + iCloudSync only); on
    ///    failure, re-attach the original store so the coordinator is never
    ///    left store-less.
    /// 5. Destroy + rebuild the local store empty (in iCloudSync this also
    ///    re-arms CloudKit mirroring, which re-imports the surviving zone for
    ///    `.redownload`).
    /// 6. Wait for CloudKit to settle (iCloudSync only).
    ///
    /// Callers must already hold `withReentrancyGuard` — this has no guard
    /// of its own, so `resetAndReseedFromThisDevice()` can wrap it together
    /// with its export/reimport/broadcast steps under one guarded call.
    ///
    /// - Parameter bypassAccountChangedGuard: `S3` — set only by
    ///   `resolveAccountMismatchByRedownloading()`, which has already
    ///   independently re-validated a mismatch is genuinely active before
    ///   calling. Every other caller (including `resetAndRedownload()`,
    ///   which `ResetSignalMonitor`'s automatic peer-triggered reset
    ///   depends on) leaves this `false` and stays subject to step 2's
    ///   ambient throw.
    private func performReset(_ scope: Scope, bypassAccountChangedGuard: Bool = false) async throws {
        let mode = await host.currentMode

        // `.redownload` only makes sense while syncing — guard before any
        // destructive work so an invalid call is a clean no-op, not a wipe.
        if scope == .redownload, mode != .iCloudSync {
            throw LillistError.storeUnavailable(
                reason: "Reset & Download needs iCloud Sync turned on — there is nothing to download in local-only mode."
            )
        }

        LillistLog.sync.notice("data store reset start scope=\(String(describing: scope), privacy: .public)")
        await breadcrumb("data store reset start")
        do {
            // 1. cancel notifications first
            if let scheduler = notificationScheduler {
                await scheduler.cancelAllPending()
            }

            // 2. account-changed pre-flight — skipped only for the one
            //    confirmed, re-validated mismatch-resolution call path.
            if !bypassAccountChangedGuard,
               let provider = accountStateProvider, await provider() == .accountChanged {
                throw LillistError.storeUnavailable(
                    reason: "iCloud account changed; aborting reset before erase."
                )
            }

            // 3. tear down + backup (disk pre-flight throws before erase)
            _ = try await host.tearDownStore(backupVia: quarantine)

            // 4. erase the CloudKit zone (only when wiping everywhere)
            if scope == .everywhere, mode == .iCloudSync {
                do {
                    _ = try await zoneEraser.eraseManagedZones(
                        in: cloudKitContainerIdentifier,
                        progress: { _ in }
                    )
                } catch {
                    // Re-attach the original store (files are still on disk)
                    // so the user isn't left store-less, then surface the
                    // failure. The local data is intact; the backup remains.
                    try? await host.reattachStore()
                    throw error
                }
            }

            // 5. destroy + rebuild empty. S12: unlike the erase-failure
            //    path above, this step had no reattach handler at all —
            //    a failure here left the coordinator store-less until
            //    the next relaunch. Mirror the erase handling: re-attach
            //    best-effort, then surface the failure.
            do {
                try await host.rebuildEmptyStore()
            } catch {
                try? await host.reattachStore()
                throw error
            }

            // 6. let CloudKit settle (iCloudSync only). For `.redownload`
            //    this is the window in which the surviving zone
            //    re-imports. S14: the destructive work above already
            //    succeeded, so a `.timedOut` result is logged, not
            //    fatal — there is nothing left to revert, and the
            //    mirroring delegate keeps draining the queue in the
            //    background after this call returns (matches
            //    `QuiesceResult.timedOut`'s own documented contract).
            if mode == .iCloudSync {
                let result = await quiesceMonitor.waitForQuiesce(
                    minQuietWindow: quiesceMinQuietWindow, hardTimeout: quiesceHardTimeout
                )
                if result == .timedOut {
                    LillistLog.sync.notice("data store reset quiesce timed out post-completion — proceeding, sync continues in background")
                    await breadcrumb("data store reset quiesce timed out, proceeding (still syncing in background)")
                }
            }

            // S23: resync the live JSON backup package to whatever the
            // reset just left the store in (empty, or re-importing from
            // CloudKit) — one chokepoint covers resetAllData/
            // resetAndRedownload/resetEverywhereToEmpty/the wipe half of
            // resetAndReseedFromThisDevice.
            await backupReconciler?.reconcileFull()
            // S21: same chokepoint clears SyncStatusMonitor's stall
            // counters — the store's connection just changed (destroy +
            // rebuild, or a fresh reattach), so any streak tracked against
            // the previous connection no longer applies.
            await syncStatusReset?()
            // X11: every performReset call destroys + rebuilds the local
            // store (step 5, above) — every watermark and the widget cache
            // are now stale, unconditionally.
            await historyWatermarksReset?()
            await widgetCacheReset?()

            LillistLog.sync.notice("data store reset completed")
            await breadcrumb("data store reset completed")
        } catch {
            LillistLog.sync.error(
                "data store reset failed error=\(String(describing: type(of: error)), privacy: .public)"
            )
            await breadcrumb("data store reset failed", success: false)
            throw error
        }
    }

    /// Diagnostic-only breadcrumb; failures are silenced.
    private func breadcrumb(_ action: String, success: Bool = true) async {
        guard let buffer = breadcrumbs else { return }
        try? await buffer.record(action: action, success: success)
    }
}
