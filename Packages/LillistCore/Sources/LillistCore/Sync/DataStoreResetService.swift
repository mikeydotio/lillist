import Foundation
import os

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

    /// In-process reentrancy guard, shared by every public entry point
    /// via `withReentrancyGuard(_:)` — a second reset while one is
    /// running would race the store teardown (or, for the reseed flow,
    /// race its own export/reimport steps). Set synchronously before the
    /// first suspension, cleared on every exit.
    private var isResetting = false

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
        importer: Importer? = nil
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
        try await withReentrancyGuard {
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
        try await withReentrancyGuard {
            try await performReset(.redownload)
        }
    }

    /// "Erase data from all devices and start over" (issue #71). Wipes
    /// local + iCloud to empty via `resetAllData()`'s exact steps, then
    /// propagates over `ResetPropagator` so every other known device
    /// converges on empty too the next time it's open and online. A no-op
    /// propagation (besides refreshing this device's roster entry) when no
    /// `propagator` was injected or no peers are known yet.
    public func resetEverywhereToEmpty() async throws {
        try await withReentrancyGuard {
            try await performReset(.everywhere)
            propagator?.broadcast(.resetToEmpty)
        }
    }

    /// "Erase data from all devices and restore all from this device's
    /// backup" (issue #71). Snapshots this device's *current* data to a
    /// throwaway temp directory, wipes local + iCloud via `resetAllData()`'s
    /// exact steps, re-imports the snapshot into the freshly-emptied store,
    /// then propagates — every other known device discards its own local
    /// state and re-downloads, converging on **this device's** data (not
    /// empty) once the re-imported rows finish exporting.
    ///
    /// Throws `storeUnavailable` if constructed without an `exporter`/
    /// `importer` (both required for this flow only — every other method
    /// works without them).
    public func resetAndReseedFromThisDevice() async throws {
        guard let exporter, let importer else {
            throw LillistError.storeUnavailable(
                reason: "Reset & Re-seed needs the export/import subsystem, which wasn't configured."
            )
        }
        try await withReentrancyGuard {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("lillist-reseed-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // 1. snapshot this device's current data BEFORE anything is wiped.
            try await exporter.export(to: tempDir)

            // 2. wipe local + iCloud (same steps resetAllData() runs).
            try await performReset(.everywhere)

            // 3. re-seed the freshly-emptied store from the snapshot; it
            //    re-exports to CloudKit normally from here.
            _ = try await importer.importBundle(at: tempDir, conflictPolicy: .replaceExisting)

            // 4. propagate, so peers know to discard their own state and
            //    re-download rather than resurrecting it.
            propagator?.broadcast(.resetAndReseed)
        }
    }

    /// Runs `operation` under the shared reentrancy guard: a second call
    /// while one is in flight throws immediately rather than racing the
    /// first one's store teardown (or, for the reseed flow, its own
    /// export/reimport steps). Centralized here — rather than inside
    /// `performReset` — so `resetAndReseedFromThisDevice()` can guard its
    /// *entire* export→wipe→reimport→broadcast sequence as one atomic unit,
    /// not just the inner wipe.
    private func withReentrancyGuard<T>(_ operation: () async throws -> T) async throws -> T {
        guard !isResetting else {
            throw LillistError.storeUnavailable(reason: "A data-store reset is already in progress.")
        }
        isResetting = true
        defer { isResetting = false }
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
    private func performReset(_ scope: Scope) async throws {
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

            // 2. account-changed pre-flight
            if let provider = accountStateProvider, await provider() == .accountChanged {
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

            // 5. destroy + rebuild empty
            try await host.rebuildEmptyStore()

            // 6. let CloudKit settle (iCloudSync only). For `.redownload`
            //    this is the window in which the surviving zone re-imports.
            if mode == .iCloudSync {
                _ = await quiesceMonitor.waitForQuiesce(minQuietWindow: 5, hardTimeout: 300)
            }

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
