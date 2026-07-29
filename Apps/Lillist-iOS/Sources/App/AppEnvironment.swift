import Foundation
import CloudKit
import Observation
import UIKit
import LillistCore
import LillistUI

/// Root @Observable environment passed into the SwiftUI hierarchy.
///
/// Construction is `async throws` because `PersistenceController.init` is —
/// it loads the Core Data store, which can fail. The app uses
/// `AppEnvironment.make()` from a `.task` modifier on the loading view.
///
/// Mirrors the macOS app's `AppEnvironment` shape, plus iOS-only stores
/// (`attachmentStore`, `preferencesStore`) used by the iOS detail tabs and
/// settings surface.
@MainActor
@Observable
final class AppEnvironment {
    /// Plan 21: the single, lifecycle-stable host wrapping the
    /// Core Data container. Mode swaps go through this; stores read
    /// `persistenceHost.controller.container.viewContext` exactly as
    /// they did when the host was a raw `PersistenceController`.
    let persistenceHost: PersistenceHost
    /// Convenience accessor that shadows the host's controller.
    /// SwiftUI surfaces and existing call sites keep their pre-Plan-21
    /// shape: `environment.persistence.container.viewContext`.
    let persistence: PersistenceController
    /// Plan 21: on-disk URL of the live SQLite store (or `nil` in
    /// tests using the in-memory store). `MigrationCoordinator`
    /// needs this so it can quarantine the file before a destructive
    /// op and restore it during recovery.
    let storeURL: URL?
    let syncModeStore: SyncModeStore
    let migrationJournalStore: any MigrationJournalStore
    let migrationCoordinator: MigrationCoordinator
    /// Debug-only full data-store reset (Settings → Debug). Wipes the
    /// local store and, when syncing, the CloudKit zone, then rebuilds
    /// empty. Reuses the same quarantine / zone-eraser / quiesce pieces
    /// as `migrationCoordinator`.
    let dataStoreReset: DataStoreResetService
    /// Issue #71: self-registering directory of this iCloud account's
    /// devices, over the iCloud Key-Value Store (a separate channel from
    /// the Core Data/CloudKit mirror — see `ResetSignalMonitor`'s doc
    /// comment for why that separation is the point).
    let deviceRoster: DeviceRoster
    /// Issue #71: watches for a reset broadcast from another device and
    /// converges this one to current iCloud state. Started in
    /// `bootstrap()`, after one launch catch-up pass.
    let resetSignalMonitor: ResetSignalMonitor
    /// Data-sync-hardening `S10`: the currently-pending, undecided reset
    /// event awaiting explicit user confirmation, mirrored off
    /// `resetSignalMonitor.pendingDecisionStream` so SwiftUI can observe it
    /// without polling. `nil` means nothing is pending.
    var pendingResetDecision: ResetControlEvent?
    /// Data-sync-hardening `S10`: the most recent reset event this device
    /// auto-discarded (expired, or not currently syncing) without ever
    /// surfacing it as a decision — mirrored off
    /// `resetSignalMonitor.discardNoticeStream` so the UI can show a real
    /// "why didn't I get asked" note instead of a silent drop.
    var resetEventDiscardNotice: ResetEventDiscardNotice?
    /// Data-sync-hardening `S18`: filesystem backup copies taken before a
    /// destructive migration/reset. Promoted to a stored property (was a
    /// local in this initializer) so `bootstrap()` can call
    /// `cleanupExpired()` — previously never wired into production at all,
    /// so quarantine copies accumulated unbounded.
    let quarantine: QuarantineManager
    /// Issue #7: keeps the on-disk JSON backup package in step with the live
    /// store (one file per task), and rolls daily snapshot zips. Retained for
    /// the app's lifetime; deinit removes its observers.
    let localBackupCoordinator: LocalBackupCoordinator
    /// Issue #7: lists / creates / prunes the timestamped snapshot zips. Read by
    /// the Data Management backup UI.
    let backupSnapshotManager: BackupSnapshotManager
    /// Issue #7: schema-gated destructive restore from a package or snapshot.
    let backupRestoreService: BackupRestoreService
    let pauseReasonClassifier: PauseReasonClassifier
    /// Data-sync-hardening `S24`: real `NWPathMonitor`-backed reachability
    /// for `pauseReasonClassifier`, promoted to its own property so
    /// `bootstrap()` can call `start()` — matches the established pattern
    /// (`resetSignalMonitor`, `taskDuplicateReconciler`, `syncMonitor`, …)
    /// of constructing in `init` and starting observation in `bootstrap()`.
    let networkReachability: LiveNetworkReachability
    /// Data-sync-hardening `S21`: the Core sync-status actor, promoted to
    /// its own property so `resetStallState()` can be injected into
    /// `migrationCoordinator`/`dataStoreReset`. `syncMonitor` (below) wraps
    /// this same instance for the UI.
    let syncStatusMonitor: SyncStatusMonitor
    /// Latest resolved sync mode, mirrored off the actor so SwiftUI
    /// can observe it.
    var currentSyncMode: SyncMode = .default
    /// Plan 21: latest classification by `PauseReasonClassifier`. `nil`
    /// when sync is active or the app is in LocalOnly mode.
    var pauseReason: PauseReason?
    let taskStore: TaskStore
    let tagStore: TagStore
    let journalStore: JournalStore
    let attachmentStore: AttachmentStore
    let preferencesStore: PreferencesStore
    let devicePreferences: DevicePreferencesStore
    let preferencesPartitionMigrator: AppPreferencesPartitionMigrator
    /// EventKit boundary for "Tasks from Reminders": list enumeration + access
    /// request (settings) and item fetch/delete (importer).
    let remindersGateway: RemindersGateway
    /// Drains the chosen Reminders list into top-level tasks on activation.
    let remindersImporter: RemindersImporter
    /// Seed text handed off by the Quick Capture App Intent via
    /// ``QuickCaptureHandoff``. Observed by `TaskEditorHost` to open the
    /// capture dialog pre-filled; reset to `nil` once consumed.
    var pendingQuickCaptureSeed: String?
    /// Filter to focus, handed off by a `lillist://filter/<id>` deep link (the
    /// widget's whole-tap target). Observed by `TasksView`, which selects it and
    /// resets this to `nil`.
    var pendingSelectedFilterID: UUID?
    /// Task to open, handed off by a `lillist://task/<id>` deep link (a widget
    /// row tap). Observed by `TasksView`, which opens it and resets this to `nil`.
    var pendingOpenTaskID: UUID?
    let seriesStore: SeriesStore
    let smartFilterStore: SmartFilterStore
    /// Regenerates the per-filter widget snapshot cache + reloads widget
    /// timelines on store changes. `nil` when the App Group is unreachable.
    let widgetRefresh: WidgetRefreshController?
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    /// Drives notification reconciliation from CloudKit imports (review
    /// notif-2). Retained for the app's lifetime; deinit removes its observer.
    let remoteChangeReconciler: RemoteChangeReconciler
    /// Issue #66: merges `LillistTask` rows that share one app `id` — the
    /// shape a resync produces when local mirroring bookkeeping is
    /// discarded/rebuilt while the CloudKit zone still holds a matching
    /// record. Retained for the app's lifetime; deinit removes its observer.
    let taskDuplicateReconciler: TaskDuplicateReconciler
    /// File-based diagnostic logging (design 2026-06-06). On-by-default in
    /// Debug/TestFlight, off in Release. Injected into the stores + drag layer.
    let diagnosticLog: DiagnosticLog
    /// Derives data-layer events from persistent history (its own watermark key,
    /// distinct from the reconciler's) and forwards them to `diagnosticLog`.
    let diagnosticHistoryObserver: DiagnosticHistoryObserver
    let notificationPermissions: NotificationPermissions
    let accountStateMonitor: AccountStateMonitor
    /// Data-sync-hardening `S3`: persists and compares this device's known
    /// iCloud account identity. `make()` consults it before constructing
    /// `PersistenceController` (so a mismatch never arms CloudKit
    /// mirroring), and it's retained here so the mismatch-resolution UI
    /// can call `adoptCurrentIdentity()` after a chosen resolution
    /// succeeds. See the plan doc
    /// `docs/superpowers/plans/2026-07-28-plan-3a-account-identity-and-status.md`.
    let accountIdentityStore: AccountIdentityStore
    /// The identity comparison `make()` ran before this environment was
    /// constructed. Informational — `accountState`/`pauseReason` (derived
    /// from `accountStateMonitor`, which re-runs the same comparison in
    /// `bootstrap()`) are the live signals the UI observes.
    let accountIdentityCheckAtLaunch: AccountIdentityStore.CheckResult
    let onboardingState: OnboardingState
    let defaultsInstaller: DefaultsInstaller
    /// Persist-6: hard-deletes trash older than the retention window.
    /// Run opportunistically at launch (`bootstrap()`) and from the iOS
    /// background-processing task (`runBackgroundPurge()`).
    let autoPurgeJob: AutoPurgeJob
    let syncMonitor: any SyncIndicatorMonitor
    let breadcrumbs: BreadcrumbBuffer
    let crashReporter: CrashReporter
    let mailTransport: MailComposerTransport
    /// Retained MetricKit subscriber. MetricKit holds subscribers
    /// weakly, so the environment owns the strong reference.
    let metricKitObserver = MetricKitObserver()
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
        initialSyncMode: SyncMode,
        syncModeStore: SyncModeStore,
        migrationJournalStore: any MigrationJournalStore,
        devicePreferences: DevicePreferencesStore,
        accountIdentityStore: AccountIdentityStore,
        accountIdentityCheckAtLaunch: AccountIdentityStore.CheckResult
    ) {
        self.persistenceHost = persistenceHost
        self.persistence = persistence
        self.storeURL = storeURL
        self.syncModeStore = syncModeStore
        self.migrationJournalStore = migrationJournalStore
        self.accountIdentityStore = accountIdentityStore
        self.accountIdentityCheckAtLaunch = accountIdentityCheckAtLaunch
        self.currentSyncMode = initialSyncMode
        self.taskStore = TaskStore(persistence: persistence)
        self.tagStore = TagStore(persistence: persistence)
        self.journalStore = JournalStore(persistence: persistence)
        self.attachmentStore = AttachmentStore(persistence: persistence)
        let preferencesStore = PreferencesStore(persistence: persistence)
        self.preferencesStore = preferencesStore
        self.devicePreferences = devicePreferences
        self.preferencesPartitionMigrator = AppPreferencesPartitionMigrator(
            preferences: preferencesStore,
            devicePreferences: devicePreferences
        )
        self.seriesStore = SeriesStore(persistence: persistence)
        let smartFilterStore = SmartFilterStore(persistence: persistence)
        self.smartFilterStore = smartFilterStore
        // Home-screen / Lock Screen widgets read a per-filter snapshot cache
        // this controller maintains; nil only if the App Group is unreachable.
        // X6: observes both local `viewContext` saves and remote CloudKit
        // imports (see the type's own doc comment) — `start()` is called
        // once in `bootstrap()`, alongside the other launch-time observers.
        if let widgetSnapshotStore = WidgetSnapshotStore(appGroupID: Self.appGroupID) {
            self.widgetRefresh = WidgetRefreshController(
                persistence: persistence,
                builder: WidgetSnapshotBuilder(smartFilterStore: smartFilterStore, snapshotStore: widgetSnapshotStore),
                reloader: SystemWidgetTimelineReloader()
            )
        } else {
            self.widgetRefresh = nil
        }
        self.onboardingState = OnboardingState(devicePreferences: devicePreferences)
        self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)
        self.autoPurgeJob = AutoPurgeJob(persistence: persistence, preferences: preferencesStore)
        let ckContainerID = StoreConfiguration.defaultCloudKitContainerIdentifier
        let accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer(identifier: ckContainerID)),
            identityStore: accountIdentityStore
        )
        self.accountStateMonitor = accountStateMonitor
        let specStore = NotificationSpecStore(persistence: persistence)
        self.notificationSpecStore = specStore

        // TODO(LIL-83): timeZone: .current defeats cross-device all-day
        // notification dedup when a user's devices are in different time
        // zones — each device resolves the same all-day anchor to a
        // different absolute instant. Known, tracked limitation (interim:
        // documented in the design doc + pinned by a KNOWN LIMITATION
        // regression test); the real fix needs a new synced "home time
        // zone" field on AppPreferences (orchestrator-gated schema change —
        // see .council/x10-all-day-timezone-dedup-posture/DECISION.md).
        // Delete this TODO and both `.current` args once LIL-83 ships.
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

        // Remote-change-driven reconcile: when CloudKit imports another
        // device's notification fire, reconcile the affected tasks so this
        // device drops its now-stale pending requests.
        // NOTE: `appGroupID` is a *static* property declared at
        // AppEnvironment.swift:210 — it is NOT a parameter or local
        // variable of `private init`, so use `Self.appGroupID` here.
        // (The same constant is used as `appGroupID` inside `make()`,
        // ~line 228, where it resolves as a shorthand for `Self.appGroupID`
        // because `make()` is also a static method — but that is a
        // different call site in a different method.)
        let historyTokens = PersistentHistoryTokenStore(appGroupID: Self.appGroupID, consumer: .remoteChangeReconciler)
        self.remoteChangeReconciler = RemoteChangeReconciler(
            persistence: persistence,
            tokenStore: historyTokens
        ) { [weak scheduler] affectedTaskIDs in
            guard let scheduler else { return }
            for taskID in affectedTaskIDs {
                await scheduler.reconcile(taskID: taskID)
            }
        }
        self.taskDuplicateReconciler = TaskDuplicateReconciler(persistence: persistence)

        // Diagnostic logging. Constructed with the build-config default; the real
        // toggle value is read from `DevicePreferencesStore` (an actor) in
        // `bootstrap()`. The history observer uses its OWN watermark key so it
        // never clobbers the reconciler's.
        let diagnosticLog = DiagnosticLog.shared(
            process: .app,
            appGroupID: Self.appGroupID,
            enabled: DiagnosticDefaults.enabledByDefault
        )
        self.diagnosticLog = diagnosticLog
        self.diagnosticHistoryObserver = DiagnosticHistoryObserver(
            persistence: persistence,
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, consumer: .diagnostics),
            sink: diagnosticLog,
            process: .app
        )
        // H6: fail-loud wiring for a computed-affected-tasks failure — same
        // property-injection precedent as taskStore/smartFilterStore below.
        self.remoteChangeReconciler.diagnosticLog = diagnosticLog

        // Real CloudKit-driven sync status: bridge LillistCore's
        // SyncStatusMonitor (fed by NSPersistentCloudKitContainer events via
        // persistence.cloudKitEventBridge) onto the UI's SyncIndicatorMonitor.
        // `start()` is invoked from bootstrap(). Replaces the old
        // IdleSyncIndicatorMonitor stub that always reported "synced just now"
        // regardless of real activity.
        // S21: promoted to its own stored property (rather than only living
        // inside the adapter) so its `resetStallState()` can be injected
        // into migrationCoordinator/dataStoreReset below.
        let syncStatusMonitor = SyncStatusMonitor(bridge: persistence.cloudKitEventBridge)
        self.syncStatusMonitor = syncStatusMonitor
        self.syncMonitor = CloudKitSyncStatusAdapter(monitor: syncStatusMonitor)

        // Plan 9: shared breadcrumb buffer + crash reporter. Canary lives
        // in the App Group container so any extension that wants to record
        // its own exit state shares the file.
        let info = Bundle.main.infoDictionary ?? [:]
        let buildVersion = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let osVersion = "iOS \(UIDevice.current.systemVersion)"
        let deviceModel = UIDevice.current.model
        let hostname = UIDevice.current.name
        let breadcrumbs = BreadcrumbBuffer()
        let mailTransport = MailComposerTransport()
        self.breadcrumbs = breadcrumbs
        self.mailTransport = mailTransport
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.crashReporter = CrashReporter(
            canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .iOSApp)),
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            hostname: hostname,
            logFetcher: OSLogFetcher(),
            breadcrumbs: breadcrumbs,
            transport: mailTransport
        )

        // Plan 9: hook the stores into the shared breadcrumb buffer.
        self.taskStore.breadcrumbs = breadcrumbs
        self.tagStore.breadcrumbs = breadcrumbs
        self.journalStore.breadcrumbs = breadcrumbs
        self.attachmentStore.breadcrumbs = breadcrumbs

        // Diagnostics: hook the stores into the shared diagnostic log.
        self.taskStore.diagnosticLog = diagnosticLog
        self.smartFilterStore.diagnosticLog = diagnosticLog

        // Plan 21: assemble the migration machinery and pause reason
        // classifier. These dangle off the env so the settings
        // surface can drive a real coordinator without crossing
        // platform boundaries.
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
        // and quarantine under the App Group container (`<root>/Backup/Package`
        // + `<root>/Backup/Snapshots`). Constructed here (ahead of
        // dataStoreReset below) so it can be injected into
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
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, consumer: .backup),
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
        // Data-sync-hardening S3: this closure was previously only wired
        // into DataStoreResetService below — MigrationCoordinator itself
        // was NEVER given an accountStateProvider in production, so its
        // own .replaceICloudWithLocal/.replaceLocalWithICloud account-
        // changed pre-flights (both closed as part of this plan) were
        // dead code until now. Defined here, ahead of both constructions,
        // so both types share the identical live signal.
        let accountStateProbe: AccountStateProviding = { [accountStateMonitor] in
            await accountStateMonitor.currentState
        }
        // S21: clears SyncStatusMonitor's stall counters on a successful
        // reconfigure/reset — see the type's own doc comment.
        let clearSyncStallState: @Sendable () async -> Void = { [syncStatusMonitor] in
            await syncStatusMonitor.resetStallState()
        }
        // X11/X12/L7: WatermarkRegistry is the single source of truth for
        // every registered history consumer's watermark — both reset
        // hygiene (clearAll(), below) and safe pruning (HistoryPruner,
        // bootstrap() further down) read/clear through the same instance
        // shape, backed by the same App Group suite the three real
        // consumers (remoteChangeReconciler/diagnosticHistoryObserver/
        // localBackupCoordinator, constructed above) already use — so
        // clearing here is guaranteed to hit the real watermarks those
        // consumers read from, not a duplicate copy. Replaces the narrow,
        // hand-maintained `HistoryWatermarks` seam `3b` landed ahead of
        // this plan (see `WatermarkRegistry`'s own doc comment).
        let watermarkRegistry = WatermarkRegistry(appGroupID: Self.appGroupID)
        let clearHistoryWatermarks: () async -> Void = {
            watermarkRegistry.clearAll()
        }
        // X11: clears + regenerates the widget cache and reloads
        // timelines. `widgetRefresh` is `nil` only when the App Group is
        // unreachable, matching every other optional use of it in this
        // file. Captures the already-assigned `self.widgetRefresh` value
        // directly (not `self`) — capturing `self`, even weakly, before
        // every stored property is initialized violates Swift's definite-
        // initialization rules inside `init`.
        let widgetRefreshForReset = self.widgetRefresh
        let clearWidgetCache: () async -> Void = {
            await widgetRefreshForReset?.resetAfterDestructiveOp()
        }
        // S19: the symmetric guard to localStoreRowCount above — never
        // wipe real local data to download from an iCloud zone that turns
        // out to have nothing in it. Reuses the same LiveCloudKitZoneEraser
        // instance-shape as migrationCoordinator/dataStoreReset below (a
        // fresh instance is cheap — it holds no state).
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

        // Debug full-reset service. Same building blocks as the migration
        // coordinator (quarantine backup, CloudKit zone eraser, quiesce
        // wait) but a distinct type: a reset is not a mode transition and
        // must not touch the migration journal. Shares `accountStateProbe`
        // (defined above, ahead of migrationCoordinator) so both types see
        // the identical live signal — the account-changed guard protects
        // against erasing the wrong account's zone after a switch.
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
        // Data-sync-hardening S10: this device's own live sync mode,
        // consulted by ResetSignalMonitor once per scan to decide whether
        // an otherwise-actionable event can be surfaced at all — a
        // localOnly device has nothing to converge to.
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
            process: .app,
            propagator: resetPropagator,
            backupReconciler: localBackupCoordinator
        )

        // Tasks from Reminders: EventKit gateway + drain importer. The
        // importer reuses the same TaskStore and device prefs as the rest of
        // the app so imported tasks are indistinguishable from hand-created ones.
        let remindersGateway = EventKitRemindersGateway()
        self.remindersGateway = remindersGateway
        self.remindersImporter = RemindersImporter(
            gateway: remindersGateway,
            taskStore: self.taskStore,
            devicePreferences: devicePreferences,
            diagnosticLog: diagnosticLog
        )
    }

    /// App Group identifier shared between the main app, Share Extension,
    /// and Shortcuts (App Intents) extension. Matches the entitlement on
    /// every target.
    static let appGroupID = "group.app.lillist"

    /// Async-friendly constructor. Loads the Core Data store inside the
    /// App Group's shared container so the Share Extension and App
    /// Intents extension see the same data. The initial sync mode is
    /// resolved from `SyncModeStore` (defaults to iCloudSync when no
    /// value is persisted yet — preserving Plan 20 upgrade behavior).
    ///
    /// Data-sync-hardening `X1` (folded-in iOS detail): this used to fall
    /// back silently to `StoreConfiguration.defaultOnDisk` (a private,
    /// per-sandbox path the Share/Shortcuts extensions and widget can't
    /// see) whenever the App Group container was unreachable — a fourth,
    /// undocumented store-location fork. `StoreLocation.resolve` now
    /// throws loud instead: an unreachable App Group is a real
    /// misconfiguration (missing entitlement, unsigned build) that must
    /// surface as a launch failure, never a silent fork onto a store the
    /// rest of the app can't share.
    static func make() async throws -> AppEnvironment {
        let syncModeStore = SyncModeStore(appGroupID: appGroupID)
        let initialMode = await syncModeStore.currentMode()
        let location = try StoreLocation.resolve(role: .mainApp, appGroupID: appGroupID)

        // Data-sync-hardening S3: compare this device's known iCloud
        // account identity BEFORE PersistenceController can arm
        // cloudKitContainerOptions. A genuine mismatch (or a storage read
        // failure — we can't verify safety, so fail closed) suppresses
        // mirroring for this launch regardless of role/mode; see the plan
        // doc §2/§4 for the full rationale and the identity-source
        // decision.
        let accountIdentityStore = AccountIdentityStore(
            storage: FileAccountIdentityStore(appGroupID: appGroupID) ?? InMemoryAccountIdentityRecordStore()
        )
        let identityCheck: AccountIdentityStore.CheckResult
        do {
            identityCheck = try accountIdentityStore.check()
        } catch {
            identityCheck = .mismatch
        }

        var config = location.makeConfiguration(syncMode: initialMode)
        if identityCheck == .mismatch {
            config.armsCloudKitMirroring = false
        }
        let persistence = try await PersistenceController(configuration: config)
        let host = PersistenceHost(controller: persistence, initialMode: initialMode)
        let devicePreferences = DevicePreferencesStore(appGroupID: appGroupID)
        let journal = FileMigrationJournalStore(appGroupID: appGroupID)
            ?? FileMigrationJournalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("Lillist-migration.json"))
        let storeURL: URL?
        if case .onDisk(let url) = config.storeKind { storeURL = url } else { storeURL = nil }
        return AppEnvironment(
            persistenceHost: host,
            persistence: persistence,
            storeURL: storeURL,
            initialSyncMode: initialMode,
            syncModeStore: syncModeStore,
            migrationJournalStore: journal,
            devicePreferences: devicePreferences,
            accountIdentityStore: accountIdentityStore,
            accountIdentityCheckAtLaunch: identityCheck
        )
    }

    /// In-memory variant for tests and previews. Mirrors `make()` but uses
    /// an `.inMemory` store. Still `async throws` because
    /// `PersistenceController.init(configuration:)` is.
    static func inMemory() async throws -> AppEnvironment {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let host = PersistenceHost(controller: persistence, initialMode: .iCloudSync)
        let suite = "AppEnvironment.inMemory-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let devicePreferences = DevicePreferencesStore(suiteName: suite)
        let syncModeStore = SyncModeStore(suiteName: suite)
        let journal = InMemoryMigrationJournalStore()
        let accountIdentityStore = AccountIdentityStore(storage: InMemoryAccountIdentityRecordStore())
        return AppEnvironment(
            persistenceHost: host,
            persistence: persistence,
            storeURL: nil,
            initialSyncMode: .iCloudSync,
            syncModeStore: syncModeStore,
            migrationJournalStore: journal,
            devicePreferences: devicePreferences,
            accountIdentityStore: accountIdentityStore,
            accountIdentityCheckAtLaunch: .firstLaunch
        )
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        // Data-sync-hardening S9b: resolve any resetAndReseedFromThisDevice
        // interrupted by a crash on a prior launch — before anything else
        // assumes the store reflects steady state. Best-effort, matching
        // every other step here.
        _ = try? await dataStoreReset.recoverInterruptedReseed()
        // Plan 21: ensure the AppPreferences row's device-local fields
        // have been copied into App Group UserDefaults before any
        // device-local consumer (OnboardingState, hotkey monitor, etc.)
        // reads from `DevicePreferencesStore`.
        _ = try? await preferencesPartitionMigrator.runIfNeeded()
        // One-shot CloudKit singleton convergence + catch-up reconcile for any
        // imports that arrived while the app wasn't running, then start
        // observing live remote changes.
        try? await preferencesStore.normalizeSingletons()
        // X10: hydrate the scheduler's all-day default from the persisted
        // preference BEFORE any reconcile pass runs below — otherwise
        // remoteChangeReconciler's own catch-up (next line) would recompute
        // (and, pre-fix, incorrectly rewrite) all-day trigger times against
        // the hardcoded 09:00 constructor default instead of the user's
        // real preference. Reuses updateDefaultAllDayTime exactly as the
        // Settings surface does — see that method's own doc comment for why
        // this call is a no-op diff in the common case, not a real rewrite.
        if let prefs = try? await preferencesStore.read() {
            await notificationScheduler.updateDefaultAllDayTime(
                hour: Int(prefs.defaultAllDayHour),
                minute: Int(prefs.defaultAllDayMinute)
            )
        }
        await remoteChangeReconciler.processPendingHistory()
        remoteChangeReconciler.start()
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
        // Data-sync-hardening S18: cleanupExpired() was never wired into
        // production before this — store copies accumulated unbounded
        // until disk-full failure started taking down every future
        // migration. Opportunistic maintenance, after the integrity/
        // singleton passes above (matches autoPurgeJob's own placement
        // further below); best-effort, matching every other step here.
        try? quarantine.cleanupExpired()
        // Issue #71: catch up on any reset broadcast that arrived while the
        // app wasn't running, then begin observing live ones.
        // Data-sync-hardening S10: refreshPendingDecision() (renamed from
        // the auto-applying checkAndApply()) only ever classifies and
        // surfaces — nothing is ever applied without explicit user
        // confirmation via the pending-decision dialog.
        await resetSignalMonitor.refreshPendingDecision()
        await resetSignalMonitor.start()
        startObservingPendingResetDecision()
        startObservingResetEventDiscardNotice()
        // Diagnostics: sync the cached enabled flag from device prefs, then run a
        // catch-up pass over any history that accrued while not running and begin
        // observing live remote changes. Order matters — set the flag first so the
        // catch-up emits honor the toggle.
        await diagnosticLog.setEnabled(await devicePreferences.diagnosticLoggingEnabled())
        await diagnosticHistoryObserver.processPendingHistory()
        diagnosticHistoryObserver.start()
        await notificationScheduler.bootstrap()
        // Persist-6: opportunistically clear expired trash at launch.
        // Errors are non-fatal — a failed purge must never block launch.
        _ = try? await autoPurgeJob.run()
        // Issue #7: start the local backup subsystem — observe live changes,
        // seed the package on first run, and roll a daily snapshot if due.
        // Best-effort; a backup error must never block launch.
        await localBackupCoordinator.bootstrapAtLaunch()
        // persist-1 / notif-7: sweep localOnly persistent history at launch so
        // it never grows unbounded. Internally gated to syncMode == .localOnly
        // (iCloudSync is a no-op); fire-and-forget — a failed prune never
        // blocks launch. X12/L7: the prune boundary comes from
        // WatermarkRegistry.pruneBoundary(in:) (min over every registered
        // consumer's own watermark), not "now" — safe regardless of whether
        // every consumer's catch-up above has actually completed.
        if let historyPruner = HistoryPruner(
            persistence: persistence,
            syncMode: await syncModeStore.currentMode(),
            appGroupID: Self.appGroupID
        ) {
            _ = try? await historyPruner.sweep()
        }
        // Bootstrap does *not* arm the canary anymore — that races
        // `CrashReporterHost.detectAndPrepare()`, which would then read
        // the just-written canary as if it were a prior crash and pop
        // the report sheet on every launch. The canary is owned by the
        // foreground-lifecycle observer below; `detectAndPrepare()`
        // sees an empty disk on a clean cold launch and a real stale
        // canary only after a true foreground crash.
        self.crashPromptsEnabled = await devicePreferences.crashPromptsEnabled()
        // S24: begin observing real network reachability before priming
        // pauseReason below, so the first classification isn't stuck on
        // the pre-start default.
        await networkReachability.start()
        // Plan 10: prime the iCloud account-state cache so the
        // onboarding gate has a non-default value to read.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        // ios-1: prime the pause-reason mirror so the sync-status badge and
        // PauseExplainerDialog read a real classification, not a stale nil.
        self.pauseReason = await pauseReasonClassifier.currentReason()
        // S13: observe CKAccountChanged so a mid-session account switch is
        // caught, not just this cold launch's own check (already applied
        // above via `accountIdentityCheckAtLaunch`/`config.armsCloudKitMirroring`).
        await accountStateMonitor.startObservingSystemAccountChanges()
        startObservingAccountState()
        startObservingMidSessionAccountMismatch()
        startObservingSyncMode()
        installCanaryLifecycleObservers()
        startObservingPauseReason()
        // Keep home-screen / Lock Screen widgets fresh: rebuild the per-filter
        // snapshot cache + reload timelines on every store change (local
        // `viewContext` saves AND CloudKit imports — X6), and warm the cache
        // once now so a freshly added widget renders immediately.
        widgetRefresh?.start()
        widgetRefresh?.refreshNow()
        // Connect the live CloudKit sync-status stream to the UI indicator.
        await syncMonitor.start()
        metricKitObserver.startReceiving()

        // Quick Capture handoff (cold launch): an App Intent may have stashed
        // seed text before launch completed. bootstrap() runs *after* the
        // launch `didBecomeActive` has already fired, so consume it here; warm
        // returns are handled by the lifecycle observer above. Instant
        // (UserDefaults read) — `TaskEditorHost` opens the dialog once the view
        // appears with this value already set.
        if let seed = QuickCaptureHandoff.take(appGroupID: Self.appGroupID) {
            self.pendingQuickCaptureSeed = seed
        }
        // Tasks from Reminders: drain the queue on launch. Fire-and-forget so a
        // slow EventKit fetch never delays the first frame; no-ops fast when
        // the feature is disabled or unauthorized.
        Task { [remindersImporter] in await remindersImporter.drainIfNeeded() }
    }

    /// Persist-6: entry point for the iOS background-processing task.
    /// Runs the trash purge off the foreground; returns whether it
    /// completed without throwing so the `BGTask` can report success.
    func runBackgroundPurge() async -> Bool {
        do {
            _ = try await autoPurgeJob.run()
            return true
        } catch {
            return false
        }
    }

    /// iOS canary lifecycle: write on foreground (didBecomeActive),
    /// delete on backgrounding (willResignActive). `willTerminate` is
    /// the wrong hook on iOS — the OS suspends apps and then kills
    /// them without firing it, so every "normal" exit would otherwise
    /// leave a stale canary behind and trigger a false crash report on
    /// the next launch.
    ///
    /// Installation happens at the end of `bootstrap()`, which on the
    /// iOS launch path completes after the initial `didBecomeActive`
    /// has already fired — so this observer doesn't write a canary on
    /// cold launch (that's `CrashReporterHost.detectAndPrepare()`'s
    /// job) and only fires on subsequent foreground returns.
    private func installCanaryLifecycleObservers() {
        let reporter = self.crashReporter
        let backup = self.localBackupCoordinator
        let accountStateMonitor = self.accountStateMonitor
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { try? await reporter.start() }
            // Issue #7: roll a daily snapshot if the app stays foregrounded
            // across a day boundary. No-op when one isn't due.
            Task { await backup.runSnapshotIfDue() }
            // S13: re-probe on every foreground return, not just
            // CKAccountChanged deliveries — a belt-and-suspenders catch
            // for any account change the notification alone might miss.
            Task { try? await accountStateMonitor.refresh() }
            // Warm reactivation: consume any Quick Capture handoff and drain
            // the Reminders queue. (Cold launch is handled in bootstrap(),
            // which runs after the first didBecomeActive.)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let seed = QuickCaptureHandoff.take(appGroupID: Self.appGroupID) {
                    self.pendingQuickCaptureSeed = seed
                }
                await self.remindersImporter.drainIfNeeded()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { _ in
            // Block briefly to give `markCleanExit` a chance to land
            // before the OS suspends us; mirrors the previous
            // `willTerminate` pattern. Without this the canary file
            // could remain on disk if suspension happens before the
            // Task runs, producing a false stale-crash next launch.
            let group = DispatchGroup()
            group.enter()
            Task {
                try? await reporter.markCleanExit()
                group.leave()
            }
            _ = group.wait(timeout: .now() + .seconds(2))
        }
    }

    /// Data-sync-hardening `S10`: stream pending-decision changes off
    /// `resetSignalMonitor` into the `@Observable` mirror so the settings
    /// UI can show/dismiss the confirmation dialog without polling.
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

    /// Data-sync-hardening `S10`: stream auto-discard notices (expired, or
    /// not currently syncing) off `resetSignalMonitor` into the
    /// `@Observable` mirror so the UI can show a real "why didn't I get
    /// asked" note instead of a silent drop.
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

    /// Data-sync-hardening `S3`/`S13`: automatically and silently sever a
    /// live CloudKit mirroring connection the instant a mismatch is
    /// detected *mid-session* — per the council decision
    /// (`.council/s3-account-mismatch-response-policy/DECISION.md`), this
    /// is non-destructive containment (no data loss, no user confirmation
    /// needed) distinct from the dismissible resolution dialog that still
    /// appears afterward via the ordinary `pauseReason` badge path.
    ///
    /// Deliberately skips the stream's FIRST value: `accountStateMonitor
    /// .stateStream` always replays the current state to a new subscriber
    /// immediately, and by the time this subscribes (after `bootstrap()`'s
    /// own `refresh()` call above), that replay already reflects
    /// whatever `accountIdentityCheckAtLaunch` found — which cold launch
    /// already handled safely via `armsCloudKitMirroring = false` in
    /// `make()`. Only a value that arrives AFTER that replay represents a
    /// genuine mid-session change (a live `CKAccountChanged` delivery or a
    /// foreground re-probe), when mirroring may actually be attached and
    /// live.
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
    /// uses — reused rather than a bespoke coordinator call, matching the
    /// existing hardened-primitives-only discipline. Best-effort: a
    /// failure here still leaves the coordinator's own failure handling
    /// (unconditional reattach) in control, and the dismissible resolution
    /// dialog remains available regardless of this call's outcome.
    private func severMirroringForMidSessionAccountMismatch() async {
        guard currentSyncMode == .iCloudSync else { return }
        let url = storeURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
        try? await migrationCoordinator.beginDisable(strategy: .now, storeURL: url)
    }

    /// Plan 21: bridge `SyncModeStore.modeStream` onto the
    /// `@Observable` mirror so views (settings toggle, status bar
    /// indicator) react immediately to mode changes from any path
    /// (Settings UI, migration coordinator, recovery flow).
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

    /// ios-1: re-classify the sync pause reason whenever the iCloud
    /// account state changes. The classifier reads the same
    /// `AccountStateMonitor`, so reacting to its stream keeps
    /// `pauseReason` consistent with `accountState`. `nil` means sync is
    /// active (or LocalOnly); the settings surface renders accordingly.
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
