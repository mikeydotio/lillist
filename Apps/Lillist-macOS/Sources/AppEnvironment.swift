import Foundation
import AppKit
import CloudKit
import Observation
import LillistCore
import LillistUI

/// Root @Observable environment passed into the SwiftUI hierarchy.
///
/// Construction is `async throws` because `PersistenceController.init` is —
/// it loads the Core Data store, which can fail. The app uses
/// `AppEnvironment.make()` from a `.task` modifier on the loading view.
@MainActor
@Observable
final class AppEnvironment {
    /// Plan 21: stable container indirection — see iOS counterpart.
    let persistenceHost: PersistenceHost
    let persistence: PersistenceController
    let storeURL: URL?
    /// Data-sync-hardening `X1`: the result of the one-time legacy-store
    /// migration `make()` runs before constructing `persistence`. Retained
    /// (rather than only logged) so the outcome is discoverable — e.g. a
    /// future Settings/diagnostics surface, or Mikey's manual-verification
    /// pass — without needing to grep breadcrumbs. Logged via
    /// `breadcrumbs` once that buffer exists, in `bootstrap()`.
    let macAppGroupMigrationOutcome: MacAppGroupMigration.Outcome
    let syncModeStore: SyncModeStore
    let migrationJournalStore: any MigrationJournalStore
    let migrationCoordinator: MigrationCoordinator
    let pauseReasonClassifier: PauseReasonClassifier
    /// Data-sync-hardening `S24`: real reachability — see the iOS
    /// counterpart's identical doc comment.
    let networkReachability: LiveNetworkReachability
    /// Data-sync-hardening `S21`: the Core sync-status actor, promoted to
    /// its own property — see the iOS counterpart's identical doc comment.
    let syncStatusMonitor: SyncStatusMonitor
    var currentSyncMode: SyncMode = .default
    /// Plan 21: latest classification by `PauseReasonClassifier`.
    var pauseReason: PauseReason?
    let taskStore: TaskStore
    let tagStore: TagStore
    let journalStore: JournalStore
    /// Attachment store. Wired on both platforms so the unified task
    /// editor's attachment section works on macOS (it previously existed
    /// only on iOS, where the detail tabs used it).
    let attachmentStore: AttachmentStore
    let seriesStore: SeriesStore
    let preferencesStore: PreferencesStore
    let devicePreferences: DevicePreferencesStore
    let preferencesPartitionMigrator: AppPreferencesPartitionMigrator
    /// EventKit boundary for "Tasks from Reminders": list enumeration + access
    /// request (Preferences pane) and item fetch/delete (importer).
    let remindersGateway: RemindersGateway
    /// Drains the chosen Reminders list into top-level tasks on activation.
    let remindersImporter: RemindersImporter
    let smartFilterStore: SmartFilterStore
    /// Regenerates the per-filter widget snapshot cache + reloads widget
    /// timelines on store changes. `nil` when the App Group is unreachable.
    let widgetRefresh: WidgetRefreshCoordinator?
    /// Filter to focus, handed off by a `lillist://filter/<id>` deep link (the
    /// widget's whole-tap target). Observed by `MacTasksView`, which selects it
    /// and resets this to `nil`.
    var pendingSelectedFilterID: UUID?
    /// Task to open, handed off by a `lillist://task/<id>` deep link (a widget
    /// row tap). Observed by `MacTasksView`, which opens it and resets to `nil`.
    var pendingOpenTaskID: UUID?
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    let notificationPermissions: NotificationPermissions
    let accountStateMonitor: AccountStateMonitor
    /// Data-sync-hardening `S3`: persists and compares this device's known
    /// iCloud account identity — see the iOS counterpart's doc comment and
    /// the plan doc
    /// `docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`.
    let accountIdentityStore: AccountIdentityStore
    /// The identity comparison `make()` ran before this environment was
    /// constructed. Informational — see the iOS counterpart's doc comment.
    let accountIdentityCheckAtLaunch: AccountIdentityStore.CheckResult
    let onboardingState: OnboardingState
    let defaultsInstaller: DefaultsInstaller
    /// Persist-6: hard-deletes trash older than the retention window.
    /// Run opportunistically at launch (`bootstrap()`). Parity with iOS.
    let autoPurgeJob: AutoPurgeJob
    /// Issue #7: full-data reset primitive (wipe local + iCloud, rebuild empty).
    /// macOS parity with iOS; used by the backup restore flow.
    let dataStoreReset: DataStoreResetService
    /// Issue #71: self-registering directory of this iCloud account's
    /// devices, over the iCloud Key-Value Store (a separate channel from
    /// the Core Data/CloudKit mirror — see `ResetSignalMonitor`'s doc
    /// comment for why that separation is the point).
    let deviceRoster: DeviceRoster
    /// Issue #71: watches for a reset broadcast from another device and
    /// converges this one to current iCloud state. Started in
    /// `bootstrap()`, after one launch catch-up pass. Runs on macOS the
    /// same way `TaskDuplicateReconciler` already does — the observer is
    /// author-agnostic (compares epochs, not `NSPersistentStoreRemoteChange`
    /// transaction authors), so macOS's lack of a `RemoteChangeReconciler`
    /// is irrelevant here.
    let resetSignalMonitor: ResetSignalMonitor
    /// Data-sync-hardening `S10`: the currently-pending, undecided reset
    /// event awaiting explicit user confirmation — see the iOS
    /// counterpart's identical doc comment.
    var pendingResetDecision: ResetControlEvent?
    /// Data-sync-hardening `S10`: the most recent reset event this device
    /// auto-discarded without ever surfacing it as a decision — see the
    /// iOS counterpart's identical doc comment.
    var resetEventDiscardNotice: ResetEventDiscardNotice?
    /// Data-sync-hardening `S18`: promoted to a stored property so
    /// `bootstrap()` can call `cleanupExpired()` — see the iOS
    /// counterpart's identical doc comment.
    let quarantine: QuarantineManager
    /// Issue #7: keeps the on-disk JSON backup package in step with the live
    /// store (one file per task) and rolls daily snapshot zips.
    let localBackupCoordinator: LocalBackupCoordinator
    /// Issue #7: lists / creates / prunes the timestamped snapshot zips.
    let backupSnapshotManager: BackupSnapshotManager
    /// Issue #7: schema-gated destructive restore from a package or snapshot.
    let backupRestoreService: BackupRestoreService
    /// Plan 11 Task 18: the global hotkey monitor lives on the
    /// environment (alongside the other singletons) so the Quick
    /// Capture preferences pane can call `reregister(combo:)` directly
    /// when the user saves a new combo. `AppDelegate.bootstrap()`
    /// configures `onHotkey` and calls `install()`.
    let hotkeyMonitor: GlobalHotkeyMonitor
    let syncMonitor: any SyncIndicatorMonitor
    let breadcrumbs: BreadcrumbBuffer
    let crashReporter: CrashReporter
    /// File-based diagnostic logging (design 2026-06-06). macOS is the FIRST
    /// persistent-history consumer here (no `RemoteChangeReconciler` exists), so
    /// the observer is net-new wiring with its own watermark key.
    let diagnosticLog: DiagnosticLog
    let diagnosticHistoryObserver: DiagnosticHistoryObserver
    /// Issue #66: merges `LillistTask` rows that share one app `id` — the
    /// shape a resync produces when local mirroring bookkeeping is
    /// discarded/rebuilt while the CloudKit zone still holds a matching
    /// record. Retained for the app's lifetime; deinit removes its observer.
    let taskDuplicateReconciler: TaskDuplicateReconciler
    var crashPromptsEnabled: Bool = PreferencesStore.Prefs.crashPromptsDefault
    /// Plan 10: latest known iCloud account state, mirrored off the
    /// `AccountStateMonitor` actor so SwiftUI views can react via
    /// `@Observable`-based observation.
    var accountState: iCloudAccountState = .noAccount
    let buildVersion: String
    let osVersion: String
    let deviceModel: String

    private init(
        persistenceHost: PersistenceHost,
        persistence: PersistenceController,
        storeURL: URL?,
        macAppGroupMigrationOutcome: MacAppGroupMigration.Outcome,
        initialSyncMode: SyncMode,
        syncModeStore: SyncModeStore,
        migrationJournalStore: any MigrationJournalStore,
        devicePreferences: DevicePreferencesStore,
        accountIdentityStore: AccountIdentityStore,
        accountIdentityCheckAtLaunch: AccountIdentityStore.CheckResult,
        initialHotkeyCombo: String = GlobalHotkeyMonitor.defaultCombo
    ) {
        self.persistenceHost = persistenceHost
        self.persistence = persistence
        self.storeURL = storeURL
        self.macAppGroupMigrationOutcome = macAppGroupMigrationOutcome
        self.syncModeStore = syncModeStore
        self.migrationJournalStore = migrationJournalStore
        self.accountIdentityStore = accountIdentityStore
        self.accountIdentityCheckAtLaunch = accountIdentityCheckAtLaunch
        self.currentSyncMode = initialSyncMode
        self.taskStore = TaskStore(persistence: persistence)
        self.tagStore = TagStore(persistence: persistence)
        self.journalStore = JournalStore(persistence: persistence)
        self.attachmentStore = AttachmentStore(persistence: persistence)
        self.seriesStore = SeriesStore(persistence: persistence)
        let preferencesStore = PreferencesStore(persistence: persistence)
        self.preferencesStore = preferencesStore
        self.devicePreferences = devicePreferences
        self.preferencesPartitionMigrator = AppPreferencesPartitionMigrator(
            preferences: preferencesStore,
            devicePreferences: devicePreferences
        )
        let smartFilterStore = SmartFilterStore(persistence: persistence)
        self.smartFilterStore = smartFilterStore
        // Desktop widgets read a per-filter snapshot cache this coordinator
        // maintains; nil only if the App Group is unreachable.
        self.widgetRefresh = WidgetRefreshCoordinator(
            smartFilterStore: smartFilterStore,
            appGroupID: Self.appGroupID
        )
        self.onboardingState = OnboardingState(devicePreferences: devicePreferences)
        self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)
        self.autoPurgeJob = AutoPurgeJob(persistence: persistence, preferences: preferencesStore)
        // Plan 11 Task 18: arm the hotkey monitor with the user's stored
        // combo before `AppDelegate.bootstrap()` calls `install()`. If
        // prefs lookup fails (or this is a brand-new install), we fall
        // back to `GlobalHotkeyMonitor.defaultCombo`.
        self.hotkeyMonitor = GlobalHotkeyMonitor(initialCombo: initialHotkeyCombo)
        let ckContainerID = StoreConfiguration.defaultCloudKitContainerIdentifier
        self.accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer(identifier: ckContainerID)),
            identityStore: accountIdentityStore
        )
        let specStore = NotificationSpecStore(persistence: persistence)
        self.notificationSpecStore = specStore

        // Bootstrap snooze + scheduler from sensible defaults. Plan 10 owns
        // wiring the live `AppPreferences` row in via
        // `scheduler.updateDefaultAllDayTime` / `installMorningSummary`.
        let registry = SnoozeRegistry(
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            timeZone: .current
        )
        self.snoozeRegistry = registry

        let scheduler = NotificationScheduler(
            persistence: persistence,
            specs: specStore,
            center: SystemUserNotificationCenter(),
            snoozeRegistry: registry,
            deviceFingerprint: DeviceFingerprint.current(),
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            timeZone: .current
        )
        self.notificationScheduler = scheduler
        self.notificationPermissions = NotificationPermissions()

        // Property injection per Plan 5: TaskStore reaches the scheduler
        // here, NOT through a singleton holder.
        self.taskStore.notificationScheduler = scheduler
        // H3: AutoPurgeJob needs the scheduler too, so a retention-window
        // purge cancels the pending OS notifications of every task it
        // removes (reconcile(taskID:) can't be reused post-purge — the row
        // is gone, so it would silently no-op).
        self.autoPurgeJob.notificationScheduler = scheduler

        // Plan 9: wire each store's breadcrumb sink to the shared buffer
        // *after* it's created below. Done in two passes because the
        // BreadcrumbBuffer field is declared later in this init.

        // Real CloudKit-driven sync status: the CloudKitSyncStatusAdapter
        // bridges LillistCore.SyncStatusMonitor's statusStream (fed by
        // NSPersistentCloudKitContainer events via
        // persistence.cloudKitEventBridge) onto the SyncIndicatorMonitor
        // protocol. `start()` is invoked from bootstrap(). Replaces the old
        // IdleSyncIndicatorMonitor stub that always reported "synced just now".
        // S21: promoted to its own stored property — see the iOS
        // counterpart's identical doc comment.
        let syncStatusMonitor = SyncStatusMonitor(bridge: persistence.cloudKitEventBridge)
        self.syncStatusMonitor = syncStatusMonitor
        self.syncMonitor = CloudKitSyncStatusAdapter(monitor: syncStatusMonitor)

        // Plan 9: shared breadcrumb buffer + crash reporter.
        let info = Bundle.main.infoDictionary ?? [:]
        let buildVersion = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let osVersion = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        let deviceModel = ProcessInfo.processInfo.hostName
        let hostname = Host.current().localizedName ?? "Mac"
        let breadcrumbs = BreadcrumbBuffer()
        self.breadcrumbs = breadcrumbs
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.crashReporter = CrashReporter(
            canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .macOSApp)),
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            hostname: hostname,
            logFetcher: OSLogFetcher(),
            breadcrumbs: breadcrumbs,
            transport: MailtoTransport()
        )

        // Now that breadcrumbs exists, hook the stores into it.
        self.taskStore.breadcrumbs = breadcrumbs
        self.tagStore.breadcrumbs = breadcrumbs
        self.journalStore.breadcrumbs = breadcrumbs
        self.attachmentStore.breadcrumbs = breadcrumbs

        // Diagnostics: shared log + net-new history observer (own watermark key).
        let diagnosticLog = DiagnosticLog.shared(
            process: .macApp,
            appGroupID: Self.appGroupID,
            enabled: DiagnosticDefaults.enabledByDefault
        )
        self.diagnosticLog = diagnosticLog
        self.diagnosticHistoryObserver = DiagnosticHistoryObserver(
            persistence: persistence,
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.diagnosticsKey),
            sink: diagnosticLog,
            process: .macApp
        )
        self.taskStore.diagnosticLog = diagnosticLog
        self.smartFilterStore.diagnosticLog = diagnosticLog
        self.taskDuplicateReconciler = TaskDuplicateReconciler(persistence: persistence)

        // Plan 21: assemble the migration machinery + classifier.
        let quarantineRoot = storeURL.map { $0.deletingLastPathComponent() }
            ?? FileManager.default.temporaryDirectory
        let quarantine = QuarantineManager(rootDirectory: quarantineRoot)
        self.quarantine = quarantine
        // data-sync-hardening S9b: durable crash-recovery journal for
        // resetAndReseedFromThisDevice — rooted alongside the quarantine
        // (same App-Group-anchored directory the reseed's own staged
        // bundle lives under), never FileManager.default.temporaryDirectory.
        let reseedJournal = FileReseedJournalStore(appGroupID: Self.appGroupID)
            ?? FileReseedJournalStore(url: quarantineRoot.appendingPathComponent("reseed.json"))
        let quiesceMonitor = SyncQuiesceMonitor(bridge: persistence.cloudKitEventBridge)
        // data-sync-hardening S11: ONE shared gate, injected into both
        // the migration coordinator and the reset service below, so a
        // migration and a reset (including one ResetSignalMonitor
        // applies automatically from a peer broadcast) can never run
        // concurrently against the same persistenceHost. Each type
        // defaults to its own private gate when none is passed — this
        // explicit shared instance is what actually closes the
        // cross-type window in production.
        let destructiveOpGate = DestructiveOpGate()

        // Issue #7: local JSON backup subsystem, rooted alongside the store
        // and quarantine under the App Group container. Constructed here
        // (ahead of dataStoreReset below) so it can be injected into
        // DataStoreResetService as backupReconciler (S23) — the reset
        // service needs the coordinator to resync the live JSON package
        // after a destructive wipe.
        let backupBase = quarantineRoot.appendingPathComponent("Backup", isDirectory: true)
        let backupPackageDirectory = backupBase.appendingPathComponent("Package", isDirectory: true)
        let backupSnapshotsDirectory = backupBase.appendingPathComponent("Snapshots", isDirectory: true)
        let backupSnapshotManager = BackupSnapshotManager(
            packageDirectory: backupPackageDirectory,
            snapshotsDirectory: backupSnapshotsDirectory
        )
        self.backupSnapshotManager = backupSnapshotManager
        let localBackupCoordinator = LocalBackupCoordinator(
            persistence: persistence,
            preferences: preferencesStore,
            store: TaskBackupStore(packageDirectory: backupPackageDirectory),
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.backupKey),
            snapshotManager: backupSnapshotManager,
            destructiveOpGate: destructiveOpGate
        )
        self.localBackupCoordinator = localBackupCoordinator

        let networkReachability = LiveNetworkReachability()
        self.networkReachability = networkReachability
        self.pauseReasonClassifier = PauseReasonClassifier(
            accountMonitor: accountStateMonitor,
            networkMonitor: networkReachability
        )
        // sync-7: the irreversible "replace iCloud with local" erase must
        // refuse to run against an empty local store. Capture the
        // (Sendable) PersistenceController and count live, non-trashed
        // task rows via its fail-closed module API — any error returns 0,
        // which the coordinator treats as "empty" and uses to block the
        // erase. An uncertain count must never bypass the guard.
        let countController = persistence
        let localStoreRowCount: @Sendable () async -> Int = {
            await countController.localTaskRowCount()
        }
        // Data-sync-hardening S3/S21: shared closures, defined here ahead
        // of both migrationCoordinator and dataStoreReset — see the iOS
        // counterpart's identical doc comment for why migrationCoordinator
        // never received an accountStateProvider before this plan.
        let accountStateProbe: AccountStateProviding = { [accountStateMonitor] in
            await accountStateMonitor.currentState
        }
        let clearSyncStallState: @Sendable () async -> Void = { [syncStatusMonitor] in
            await syncStatusMonitor.resetStallState()
        }
        // X11: clears every persistent-history watermark after a
        // destroy/rebuild — see the iOS counterpart's identical doc
        // comment and `HistoryWatermarks`' own doc comment. macOS has no
        // `RemoteChangeReconciler` of its own, but the `defaultKey`
        // watermark is still cleared for consistency/forward-compat —
        // clearing an absent key is a harmless no-op.
        let historyWatermarks = HistoryWatermarks(
            reconciler: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.defaultKey),
            diagnostics: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.diagnosticsKey),
            backup: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.backupKey),
            prunerDefaults: UserDefaults(suiteName: Self.appGroupID) ?? .standard
        )
        let clearHistoryWatermarks: () async -> Void = {
            historyWatermarks.clearAll()
        }
        // X11: clears + regenerates the widget cache and reloads
        // timelines — see the iOS counterpart's identical doc comment
        // (including why this captures the already-assigned
        // `self.widgetRefresh` value directly rather than `self`).
        let widgetRefreshForReset = self.widgetRefresh
        let clearWidgetCache: () async -> Void = {
            await widgetRefreshForReset?.resetAfterDestructiveOp()
        }
        // S19: the symmetric guard to localStoreRowCount above — see the
        // iOS counterpart's identical doc comment.
        let remoteZoneHasRecords: @Sendable () async throws -> Bool = {
            try await LiveCloudKitZoneEraser().hasAnyRecords(in: ckContainerID)
        }
        self.migrationCoordinator = MigrationCoordinator(
            host: persistenceHost,
            journal: migrationJournalStore,
            quarantine: quarantine,
            zoneEraser: LiveCloudKitZoneEraser(),
            quiesceMonitor: quiesceMonitor,
            notificationScheduler: scheduler,
            preferencesStore: preferencesStore,
            syncModeStore: syncModeStore,
            breadcrumbs: breadcrumbs,
            cloudKitContainerIdentifier: ckContainerID,
            localStoreRowCount: localStoreRowCount,
            accountStateProvider: accountStateProbe,
            destructiveOpGate: destructiveOpGate,
            syncStatusReset: clearSyncStallState,
            historyWatermarksReset: clearHistoryWatermarks,
            widgetCacheReset: clearWidgetCache,
            remoteZoneHasRecords: remoteZoneHasRecords
        )
        // Issue #71: the reset-propagation control channel, over iCloud
        // Key-Value Store — a separate iCloud subsystem from the Core
        // Data/CloudKit mirror, so it survives exactly the kind of wedged
        // export queue issue #66 diagnosed. Register this device in the
        // roster now (independent of whether it ever triggers a reset,
        // so it's discoverable as a fan-out target for peers that do).
        let deviceID = DeviceFingerprint.current()
        let keyValueSyncStore = LiveKeyValueSyncStore()
        let deviceRoster = DeviceRoster(kv: keyValueSyncStore)
        deviceRoster.register(id: deviceID, displayName: hostname)
        self.deviceRoster = deviceRoster
        let controlInbox = ControlInbox(kv: keyValueSyncStore)
        let resetPropagator = ResetPropagator(
            roster: deviceRoster, inbox: controlInbox,
            deviceID: deviceID, deviceDisplayName: hostname
        )

        // Issue #7: full-data reset primitive (parity with iOS) — the
        // destructive half of a backup restore. Shares `accountStateProbe`/
        // `clearSyncStallState` (defined above) with migrationCoordinator.
        self.dataStoreReset = DataStoreResetService(
            host: persistenceHost,
            quarantine: quarantine,
            zoneEraser: LiveCloudKitZoneEraser(),
            quiesceMonitor: quiesceMonitor,
            notificationScheduler: scheduler,
            cloudKitContainerIdentifier: ckContainerID,
            accountStateProvider: accountStateProbe,
            breadcrumbs: breadcrumbs,
            propagator: resetPropagator,
            exporter: Exporter(persistence: persistence, preferences: preferencesStore),
            importer: Importer(persistence: persistence),
            destructiveOpGate: destructiveOpGate,
            reseedJournal: reseedJournal,
            backupReconciler: localBackupCoordinator,
            syncStatusReset: clearSyncStallState,
            historyWatermarksReset: clearHistoryWatermarks,
            widgetCacheReset: clearWidgetCache
        )
        // Data-sync-hardening S10: see the iOS counterpart's identical
        // doc comment.
        let resetMonitorSyncMode: @Sendable () async -> SyncMode = { [persistenceHost] in
            await persistenceHost.currentMode
        }
        self.resetSignalMonitor = ResetSignalMonitor(
            inbox: controlInbox,
            applied: AppliedEventStore(),
            deviceID: deviceID,
            breadcrumbs: breadcrumbs,
            currentSyncMode: resetMonitorSyncMode,
            deadLetters: ResetEventDeadLetterStore()
        ) { [dataStoreReset] _ in
            try await dataStoreReset.resetAndRedownload()
        }

        self.backupRestoreService = BackupRestoreService(
            reset: self.dataStoreReset,
            importer: Importer(persistence: persistence),
            preferences: preferencesStore,
            packageDirectory: backupPackageDirectory,
            diagnosticLog: diagnosticLog,
            process: .macApp,
            propagator: resetPropagator,
            backupReconciler: localBackupCoordinator
        )

        // Tasks from Reminders: EventKit gateway + drain importer (iOS parity).
        let remindersGateway = EventKitRemindersGateway()
        self.remindersGateway = remindersGateway
        self.remindersImporter = RemindersImporter(
            gateway: remindersGateway,
            taskStore: self.taskStore,
            devicePreferences: devicePreferences,
            diagnosticLog: diagnosticLog
        )
    }

    /// App Group identifier shared with the iOS app, extensions, and CLI.
    static let appGroupID = "group.app.lillist"

    /// Async-friendly constructor. Loads the Core Data store and wires up
    /// every store / scheduler used by the SwiftUI hierarchy.
    ///
    /// Data-sync-hardening `X1`: before this fix, macOS built its store
    /// from `StoreConfiguration.defaultOnDisk` (the sandbox Application
    /// Support container) unconditionally, never joining the App Group
    /// the iOS app, widget, and extensions share. `make()` now runs a
    /// one-time migration (`MacAppGroupMigration`) BEFORE constructing
    /// any `PersistenceController` — a pure file-system operation on two
    /// closed stores — then resolves the App-Group location through
    /// `StoreLocation`, matching every other role. See
    /// `docs/superpowers/plans/2026-07-28-plan-1c-store-location-unification.md`
    /// for the full state machine and the both-stores-populated council
    /// decision.
    static func make() async throws -> AppEnvironment {
        let syncModeStore = SyncModeStore(appGroupID: appGroupID)
        let initialMode = await syncModeStore.currentMode()

        let location = try StoreLocation.resolve(role: .mainApp, appGroupID: appGroupID)
        let legacyConfig = try StoreConfiguration.defaultOnDisk
        guard case .onDisk(let legacyURL) = legacyConfig.storeKind else {
            preconditionFailure("StoreConfiguration.defaultOnDisk always returns an onDisk storeKind")
        }
        // Rooted at the App-Group Lillist directory — the same root the
        // rest of the app's quarantine/backup subsystems use once
        // `persistence` exists (see `quarantineRoot` further below).
        let migrationQuarantine = QuarantineManager(rootDirectory: location.url.deletingLastPathComponent())
        let migrationOutcome = try MacAppGroupMigration.migrateIfNeeded(
            legacyURL: legacyURL,
            groupURL: location.url,
            syncMode: initialMode,
            quarantine: migrationQuarantine
        )
        // `.conflictDetected`/`.migrationFailed` deliberately fall back to
        // booting on the legacy store this launch — never a silent fork
        // onto a NEW, third location, just a temporary continuation of
        // today's behavior until the next launch's migration attempt (or,
        // for `.conflictDetected` in `.localOnly` mode, until the App
        // Group is manually reconciled — see the council decision).
        let resolvedURL: URL
        switch migrationOutcome {
        case .notNeeded, .migrated, .migratedResolvingConflict:
            resolvedURL = location.url
        case .conflictDetected, .migrationFailed:
            resolvedURL = legacyURL
        }
        var baseConfig = StoreConfiguration.onDisk(url: resolvedURL, syncMode: initialMode)
        baseConfig.armsCloudKitMirroring = location.mayArmCloudKitMirroring

        // Data-sync-hardening S3: compare this device's known iCloud
        // account identity BEFORE PersistenceController can arm
        // cloudKitContainerOptions — see the iOS counterpart's identical
        // comment and the plan doc §2/§4. Runs on `resolvedURL` (whichever
        // store the App-Group migration above landed on), independent of
        // that migration's own outcome.
        let accountIdentityStore = AccountIdentityStore(
            storage: FileAccountIdentityStore(appGroupID: appGroupID) ?? InMemoryAccountIdentityRecordStore()
        )
        let identityCheck: AccountIdentityStore.CheckResult
        do {
            identityCheck = try accountIdentityStore.check()
        } catch {
            identityCheck = .mismatch
        }
        if identityCheck == .mismatch {
            baseConfig.armsCloudKitMirroring = false
        }

        // Stamp the Mac's distinct author so the diagnostics observer can tell
        // Mac-authored writes apart from iOS on the same iCloud account. Safe:
        // macOS has no RemoteChangeReconciler, so no local-vs-foreign filter
        // depends on this matching localTransactionAuthor.
        let persistence = try await PersistenceController(configuration: baseConfig, transactionAuthor: PersistenceController.macAppTransactionAuthor)
        let host = PersistenceHost(controller: persistence, initialMode: initialMode)
        // Plan 21: device-local preferences live in App Group
        // UserDefaults so they survive destructive sync-mode migrations
        // and stay readable from the CLI / extensions.
        let devicePreferences = DevicePreferencesStore(appGroupID: appGroupID)
        let journal = FileMigrationJournalStore(appGroupID: appGroupID)
            ?? FileMigrationJournalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("Lillist-migration.json"))
        // Plan 11 Task 18: read the user's saved hotkey combo before
        // instantiating so the monitor is armed with the right combo
        // when `AppDelegate.bootstrap()` calls `install()`. Plan 21
        // moves the hotkey to `DevicePreferencesStore`; the partition
        // migrator (run during `bootstrap()`) ensures the App Group
        // copy is fresh on the next launch, so on first launch we may
        // see the default — that's the intended one-launch lag rather
        // than a regression.
        let combo = await devicePreferences.quickCaptureHotkey()
        let storeURL: URL?
        if case .onDisk(let url) = baseConfig.storeKind { storeURL = url } else { storeURL = nil }
        let env = AppEnvironment(
            persistenceHost: host,
            persistence: persistence,
            storeURL: storeURL,
            macAppGroupMigrationOutcome: migrationOutcome,
            initialSyncMode: initialMode,
            syncModeStore: syncModeStore,
            migrationJournalStore: journal,
            devicePreferences: devicePreferences,
            accountIdentityStore: accountIdentityStore,
            accountIdentityCheckAtLaunch: identityCheck,
            initialHotkeyCombo: combo
        )
        return env
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        // Data-sync-hardening S9b: resolve any resetAndReseedFromThisDevice
        // interrupted by a crash on a prior launch — before anything else
        // assumes the store reflects steady state. Best-effort, matching
        // every other step here.
        _ = try? await dataStoreReset.recoverInterruptedReseed()
        // Data-sync-hardening X1: record the store-migration outcome
        // computed in make() (before breadcrumbs existed) now that the
        // buffer is available — so a both-stores-populated conflict or a
        // failed migration attempt is discoverable in crash reports, not
        // silently invisible. Best-effort, matching every other step here.
        try? await recordMacAppGroupMigrationOutcome()
        // Plan 21: copy the AppPreferences row's device-local fields
        // forward into App Group UserDefaults if we haven't already.
        // Idempotent; subsequent launches no-op.
        _ = try? await preferencesPartitionMigrator.runIfNeeded()
        // Diagnostics: sync the cached flag from device prefs, catch up on
        // history accrued while not running, then observe live remote changes.
        await diagnosticLog.setEnabled(await devicePreferences.diagnosticLoggingEnabled())
        await diagnosticHistoryObserver.processPendingHistory()
        diagnosticHistoryObserver.start()
        // Issue #66: catch up on any duplicate LillistTask rows that arrived
        // while the app wasn't running (e.g. a restore performed on a prior
        // launch), then begin observing live remote changes.
        await taskDuplicateReconciler.reconcileNow()
        taskDuplicateReconciler.start()
        // Data-sync-hardening plan 1a: self-heal any illegal tree state a
        // CloudKit merge produced (parent cycles, live-under-trashed nodes,
        // position ties) — runs after duplicate reconcile (so a stale
        // duplicate can't masquerade as a cycle-break tie or a false
        // live-under-trashed positive) and before autoPurgeJob below (so
        // purge never sees an illegal state to begin with). Best-effort,
        // matching every other step here — a failed repair must never
        // block launch.
        await persistence.container.viewContext.perform { [self] in
            guard let violations = try? TreeIntegrityChecker.repair(in: persistence.container.viewContext),
                  !violations.isEmpty else { return }
            try? persistence.container.viewContext.save()
        }
        // Data-sync-hardening S18: see the iOS counterpart's identical
        // doc comment.
        try? quarantine.cleanupExpired()
        // Issue #71: catch up on any reset broadcast that arrived while the
        // app wasn't running, then begin observing live ones.
        // Data-sync-hardening S10: see the iOS counterpart's identical
        // doc comment.
        await resetSignalMonitor.refreshPendingDecision()
        await resetSignalMonitor.start()
        startObservingPendingResetDecision()
        startObservingResetEventDiscardNotice()
        await notificationScheduler.bootstrap()
        // Persist-6: opportunistically clear expired trash at launch.
        _ = try? await autoPurgeJob.run()
        // Issue #7: start the local backup subsystem — observe live changes,
        // seed the package on first run, and roll a daily snapshot if due.
        // Best-effort; a backup error must never block launch.
        await localBackupCoordinator.bootstrapAtLaunch()
        // persist-1 / notif-7: sweep localOnly persistent history at launch so
        // it never grows unbounded. Internally gated to syncMode == .localOnly
        // (iCloudSync is a no-op); fire-and-forget — a failed prune never
        // blocks launch.
        if let historyPruner = HistoryPruner(
            persistence: persistence,
            syncMode: await syncModeStore.currentMode(),
            appGroupID: Self.appGroupID
        ) {
            _ = try? await historyPruner.sweep()
        }
        // The canary is armed lazily by `CrashReporterHost.task` calling
        // `detectAndPrepare()`. Bootstrap *used* to call `start()` here
        // "defensively in case the host never gets a chance to render,"
        // but that wrote a canary which `detectAndPrepare()` then read
        // back as if it were a prior crash — popping the report sheet
        // on every launch. macOS's `applicationWillTerminate` hook in
        // AppDelegate continues to delete the canary on clean exit.
        // Hydrate crashPromptsEnabled from device-local preferences.
        self.crashPromptsEnabled = await devicePreferences.crashPromptsEnabled()
        // S24: begin observing real network reachability before priming
        // pauseReason below — see the iOS counterpart's identical comment.
        await networkReachability.start()
        // Plan 10: prime the iCloud account-state cache so the onboarding
        // gate has a non-default value to read. Errors fall through; the
        // gate handles `.noAccount` as the "iCloud unavailable" branch.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        // ios-1 parity: prime the pause-reason mirror the Preferences sync
        // pane reads, so the macOS classifier stops being dead too.
        self.pauseReason = await pauseReasonClassifier.currentReason()
        // S13: observe CKAccountChanged so a mid-session account switch is
        // caught, not just this cold launch's own check (already applied
        // above via `accountIdentityCheckAtLaunch`/`baseConfig.armsCloudKitMirroring`).
        await accountStateMonitor.startObservingSystemAccountChanges()
        startObservingAccountState()
        startObservingMidSessionAccountMismatch()
        startObservingSyncMode()
        startObservingPauseReason()
        // Keep desktop widgets fresh: rebuild the per-filter snapshot cache +
        // reload timelines on every store change (local writes AND CloudKit
        // imports), and warm the cache once now.
        startObservingStoreChangesForWidgets()
        widgetRefresh?.refreshNow()
        // Connect the live CloudKit sync-status stream to the UI indicator.
        await syncMonitor.start()

        // Tasks from Reminders: drain on launch + on every reactivation. macOS
        // has no prior foreground-activation hook, so this observer is net-new.
        installActivationDrain()
        Task { [remindersImporter] in await remindersImporter.drainIfNeeded() }
    }

    /// Log `macAppGroupMigrationOutcome` as a breadcrumb. A no-op for the
    /// steady-state `.notNeeded` case (nothing interesting happened); the
    /// remaining cases are all things Mikey's manual-verification pass
    /// (or a future diagnostics surface) should be able to discover —
    /// especially `.conflictDetected`/`.migrationFailed`, which mean this
    /// Mac is still running on the legacy store this launch.
    private func recordMacAppGroupMigrationOutcome() async throws {
        let description: String
        switch macAppGroupMigrationOutcome {
        case .notNeeded:
            return
        case .migrated(let quarantinedLegacyAt):
            description = "macAppGroupMigration.migrated quarantinedLegacyAt=\(quarantinedLegacyAt.path)"
        case .migratedResolvingConflict(let quarantinedAppGroupAt, let quarantinedLegacyAt, let legacy, let appGroup):
            description = "macAppGroupMigration.migratedResolvingConflict quarantinedAppGroupAt=\(quarantinedAppGroupAt.path) quarantinedLegacyAt=\(quarantinedLegacyAt.path) legacy=\(legacy.sizeBytes)B appGroup=\(appGroup.sizeBytes)B"
        case .conflictDetected(let legacy, let appGroup):
            description = "macAppGroupMigration.conflictDetected (localOnly, no mutation) legacy=\(legacy.sizeBytes)B appGroup=\(appGroup.sizeBytes)B — booting on legacy store"
        case .migrationFailed(let reason):
            description = "macAppGroupMigration.migrationFailed reason=\(reason) — booting on legacy store"
        }
        try await breadcrumbs.record(action: description, success: true)
    }

    /// Rebuild the widget snapshot cache whenever the store changes. The
    /// coordinator debounces, so a burst of writes coalesces into one rebuild +
    /// one timeline reload. Fires for local writes and CloudKit imports alike;
    /// registered app-lifetime (matching the other bootstrap observers).
    private func startObservingStoreChangesForWidgets() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.widgetRefresh?.scheduleRefresh()
            }
        }
    }

    /// Drain the Reminders queue whenever the app becomes active. Fire-and-
    /// forget; the importer no-ops fast when the feature is off or unauthorized.
    private func installActivationDrain() {
        let accountStateMonitor = self.accountStateMonitor
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.remindersImporter.drainIfNeeded()
            }
            // S13: re-probe on every foreground return, not just
            // CKAccountChanged deliveries — belt-and-suspenders parity
            // with iOS's identical hook.
            Task { try? await accountStateMonitor.refresh() }
        }
    }

    /// Data-sync-hardening `S3`/`S13`: automatically and silently sever a
    /// live CloudKit mirroring connection the instant a mismatch is
    /// detected mid-session — see the iOS counterpart's identical doc
    /// comment and the council decision
    /// (`.council/s3-account-mismatch-response-policy/DECISION.md`).
    private func startObservingMidSessionAccountMismatch() {
        let monitor = self.accountStateMonitor
        Task { [weak self] in
            var iterator = await monitor.stateStream.makeAsyncIterator()
            _ = await iterator.next() // skip cold-launch replay
            while let state = await iterator.next() {
                guard state == .accountChanged else { continue }
                await self?.severMirroringForMidSessionAccountMismatch()
            }
        }
    }

    /// Detach CloudKit mirroring immediately by driving the same
    /// `.disableNow` transition the "Stay Local For Now" resolution button
    /// uses — see the iOS counterpart's identical doc comment.
    private func severMirroringForMidSessionAccountMismatch() async {
        guard currentSyncMode == .iCloudSync else { return }
        let url = storeURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
        try? await migrationCoordinator.beginDisable(strategy: .now, storeURL: url)
    }

    /// Data-sync-hardening `S10`: see the iOS counterpart's identical doc
    /// comment.
    private func startObservingPendingResetDecision() {
        let monitor = self.resetSignalMonitor
        Task { [weak self] in
            for await decision in await monitor.pendingDecisionStream {
                await MainActor.run {
                    self?.pendingResetDecision = decision
                }
            }
        }
    }

    /// Data-sync-hardening `S10`: see the iOS counterpart's identical doc
    /// comment.
    private func startObservingResetEventDiscardNotice() {
        let monitor = self.resetSignalMonitor
        Task { [weak self] in
            for await notice in await monitor.discardNoticeStream {
                await MainActor.run {
                    self?.resetEventDiscardNotice = notice
                }
            }
        }
    }

    /// Plan 10: stream account-state changes off the actor into the
    /// `@Observable` mirror so views update without polling.
    private func startObservingAccountState() {
        let monitor = self.accountStateMonitor
        Task { [weak self] in
            for await state in await monitor.stateStream {
                await MainActor.run {
                    self?.accountState = state
                }
            }
        }
    }

    /// Plan 21: bridge `SyncModeStore.modeStream` onto the
    /// `@Observable` mirror so the Preferences pane and status
    /// surfaces react immediately to mode changes.
    private func startObservingSyncMode() {
        let store = self.syncModeStore
        Task { [weak self] in
            for await mode in await store.modeStream {
                await MainActor.run {
                    self?.currentSyncMode = mode
                }
            }
        }
    }

    /// ios-1 parity: re-classify the sync pause reason on every iCloud
    /// account-state change so the macOS sync surface mirrors the live
    /// reason rather than a stale nil.
    private func startObservingPauseReason() {
        let monitor = self.accountStateMonitor
        let classifier = self.pauseReasonClassifier
        Task { [weak self] in
            for await _ in await monitor.stateStream {
                let reason = await classifier.currentReason()
                await MainActor.run {
                    self?.pauseReason = reason
                }
            }
        }
    }
}
