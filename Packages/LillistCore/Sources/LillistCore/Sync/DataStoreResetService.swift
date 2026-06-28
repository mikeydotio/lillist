import Foundation
import os

/// Performs an **irreversible data-store reset** for recovering from a
/// suspected-corrupt store. Two flavors, both of which back up to
/// quarantine, destroy the local store, and rebuild it empty:
///
/// - `resetAllData()` ("Reset Everywhere") also erases the CloudKit zone
///   when syncing, so every device on the account loses its data — the
///   user-chosen "wipe everything" behavior, not a local-only cache flush.
/// - `resetAndRedownload()` ("Reset & Download") leaves the CloudKit zone
///   intact, so the rebuilt empty store re-imports the account's data —
///   a local-only rebuild that recovers from the cloud.
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

    /// In-process reentrancy guard — a second `resetAllData` while one is
    /// running would race the store teardown. Set synchronously before the
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
        breadcrumbs: BreadcrumbBuffer? = nil
    ) {
        self.host = host
        self.quarantine = quarantine
        self.zoneEraser = zoneEraser
        self.quiesceMonitor = quiesceMonitor
        self.notificationScheduler = notificationScheduler
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.accountStateProvider = accountStateProvider
        self.breadcrumbs = breadcrumbs
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

    /// Wipe every task on this device **and** in iCloud (on every device on
    /// the account), then rebuild an empty store. See `performReset` for the
    /// ordered, invariant-preserving steps.
    public func resetAllData() async throws {
        try await performReset(.everywhere)
    }

    /// Delete only this device's local copy and re-download everything from
    /// iCloud. The CloudKit zone is left untouched, so the rebuilt empty
    /// store re-imports the account's data via
    /// `NSPersistentCloudKitContainer` (which re-imports a zone whenever the
    /// local store has no import-history metadata — exactly the state a
    /// destroy+rebuild leaves it in). Use this to recover from suspected
    /// **local** corruption without losing the iCloud copy.
    ///
    /// Throws when not syncing: in local-only mode there is no CloudKit copy
    /// to download, so this would be a plain (unrecoverable-from-cloud) wipe
    /// — the caller should use `resetAllData()` if that is the intent.
    public func resetAndRedownload() async throws {
        try await performReset(.redownload)
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
    private func performReset(_ scope: Scope) async throws {
        guard !isResetting else {
            throw LillistError.storeUnavailable(reason: "A data-store reset is already in progress.")
        }
        isResetting = true
        defer { isResetting = false }

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
