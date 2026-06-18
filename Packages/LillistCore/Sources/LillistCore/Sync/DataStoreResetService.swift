import Foundation
import os

/// Performs a **full, irreversible data-store reset** for debugging a
/// suspected-corrupt store: it backs up, erases the CloudKit zone (when
/// syncing), destroys the local store, and rebuilds it empty. All
/// devices on the account lose their data — this is the user-chosen
/// "wipe everything" behavior, not a local-only cache flush.
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

    /// Wipe every task on this device and (when syncing) in iCloud, then
    /// rebuild an empty store. Steps are ordered to preserve the
    /// codebase's destructive-op invariants:
    ///
    /// 1. Cancel pending notifications first, so a wipe never leaves
    ///    stale fires pointing at deleted rows (skeptic G9).
    /// 2. Account-changed pre-flight: never erase a zone if the signed-in
    ///    account changed out from under us.
    /// 3. Tear down + quarantine backup — `copyStore`'s disk-space
    ///    pre-flight throws **before** the irreversible erase (blind-spot #5).
    /// 4. Erase the CloudKit zone (iCloudSync only); on failure, re-attach
    ///    the original store so the coordinator is never left store-less.
    /// 5. Destroy + rebuild the local store empty.
    /// 6. Wait for CloudKit to settle (iCloudSync only).
    public func resetAllData() async throws {
        guard !isResetting else {
            throw LillistError.storeUnavailable(reason: "A data-store reset is already in progress.")
        }
        isResetting = true
        defer { isResetting = false }

        LillistLog.sync.notice("data store reset start")
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

            let mode = await host.currentMode

            // 3. tear down + backup (disk pre-flight throws before erase)
            _ = try await host.tearDownStore(backupVia: quarantine)

            // 4. erase the CloudKit zone (iCloudSync only)
            if mode == .iCloudSync {
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

            // 6. let CloudKit settle (iCloudSync only)
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
