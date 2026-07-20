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
    let widgetRefresh: WidgetRefreshCoordinator?
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    /// Drives notification reconciliation from CloudKit imports (review
    /// notif-2). Retained for the app's lifetime; deinit removes its observer.
    let remoteChangeReconciler: RemoteChangeReconciler
    /// File-based diagnostic logging (design 2026-06-06). On-by-default in
    /// Debug/TestFlight, off in Release. Injected into the stores + drag layer.
    let diagnosticLog: DiagnosticLog
    /// Derives data-layer events from persistent history (its own watermark key,
    /// distinct from the reconciler's) and forwards them to `diagnosticLog`.
    let diagnosticHistoryObserver: DiagnosticHistoryObserver
    let notificationPermissions: NotificationPermissions
    let accountStateMonitor: AccountStateMonitor
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
        devicePreferences: DevicePreferencesStore
    ) {
        self.persistenceHost = persistenceHost
        self.persistence = persistence
        self.storeURL = storeURL
        self.syncModeStore = syncModeStore
        self.migrationJournalStore = migrationJournalStore
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
        // this coordinator maintains; nil only if the App Group is unreachable.
        self.widgetRefresh = WidgetRefreshCoordinator(
            smartFilterStore: smartFilterStore,
            appGroupID: Self.appGroupID
        )
        self.onboardingState = OnboardingState(devicePreferences: devicePreferences)
        self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)
        self.autoPurgeJob = AutoPurgeJob(persistence: persistence, preferences: preferencesStore)
        let ckContainerID = StoreConfiguration.defaultCloudKitContainerIdentifier
        let accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer(identifier: ckContainerID))
        )
        self.accountStateMonitor = accountStateMonitor
        let specStore = NotificationSpecStore(persistence: persistence)
        self.notificationSpecStore = specStore

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
        let historyTokens = PersistentHistoryTokenStore(appGroupID: Self.appGroupID)
        self.remoteChangeReconciler = RemoteChangeReconciler(
            persistence: persistence,
            tokenStore: historyTokens
        ) { [weak scheduler] affectedTaskIDs in
            guard let scheduler else { return }
            for taskID in affectedTaskIDs {
                await scheduler.reconcile(taskID: taskID)
            }
        }

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
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.diagnosticsKey),
            sink: diagnosticLog,
            process: .app
        )

        // Real CloudKit-driven sync status: bridge LillistCore's
        // SyncStatusMonitor (fed by NSPersistentCloudKitContainer events via
        // persistence.cloudKitEventBridge) onto the UI's SyncIndicatorMonitor.
        // `start()` is invoked from bootstrap(). Replaces the old
        // IdleSyncIndicatorMonitor stub that always reported "synced just now"
        // regardless of real activity.
        self.syncMonitor = CloudKitSyncStatusAdapter(
            monitor: SyncStatusMonitor(bridge: persistence.cloudKitEventBridge)
        )

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
        let quiesceMonitor = SyncQuiesceMonitor(bridge: persistence.cloudKitEventBridge)
        self.pauseReasonClassifier = PauseReasonClassifier(
            accountMonitor: accountStateMonitor,
            networkMonitor: ConstantNetworkReachability(reachable: true)
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
            localStoreRowCount: localStoreRowCount
        )
        // Debug full-reset service. Same building blocks as the migration
        // coordinator (quarantine backup, CloudKit zone eraser, quiesce
        // wait) but a distinct type: a reset is not a mode transition and
        // must not touch the migration journal. The account-changed probe
        // guards against erasing the wrong account's zone after a switch.
        let resetAccountProbe: AccountStateProviding = { [accountStateMonitor] in
            await accountStateMonitor.currentState
        }
        self.dataStoreReset = DataStoreResetService(
            host: persistenceHost,
            quarantine: quarantine,
            zoneEraser: LiveCloudKitZoneEraser(),
            quiesceMonitor: quiesceMonitor,
            notificationScheduler: scheduler,
            cloudKitContainerIdentifier: ckContainerID,
            accountStateProvider: resetAccountProbe,
            breadcrumbs: breadcrumbs
        )

        // Issue #7: local JSON backup subsystem, rooted alongside the store and
        // quarantine under the App Group container (`<root>/Backup/Package` +
        // `<root>/Backup/Snapshots`).
        let backupBase = quarantineRoot.appendingPathComponent("Backup", isDirectory: true)
        let backupPackageDirectory = backupBase.appendingPathComponent("Package", isDirectory: true)
        let backupSnapshotsDirectory = backupBase.appendingPathComponent("Snapshots", isDirectory: true)
        let backupSnapshotManager = BackupSnapshotManager(
            packageDirectory: backupPackageDirectory,
            snapshotsDirectory: backupSnapshotsDirectory
        )
        self.backupSnapshotManager = backupSnapshotManager
        self.localBackupCoordinator = LocalBackupCoordinator(
            persistence: persistence,
            preferences: preferencesStore,
            store: TaskBackupStore(packageDirectory: backupPackageDirectory),
            tokenStore: PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.backupKey),
            snapshotManager: backupSnapshotManager
        )
        self.backupRestoreService = BackupRestoreService(
            reset: self.dataStoreReset,
            importer: Importer(persistence: persistence),
            preferences: preferencesStore,
            packageDirectory: backupPackageDirectory
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
    static func make() async throws -> AppEnvironment {
        let syncModeStore = SyncModeStore(appGroupID: appGroupID)
        let initialMode = await syncModeStore.currentMode()
        var config: StoreConfiguration
        if let group = StoreConfiguration.appGroupOnDisk(groupID: appGroupID, syncMode: initialMode) {
            config = group
        } else {
            config = try StoreConfiguration.defaultOnDisk.withSyncMode(initialMode)
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
            devicePreferences: devicePreferences
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
        return AppEnvironment(
            persistenceHost: host,
            persistence: persistence,
            storeURL: nil,
            initialSyncMode: .iCloudSync,
            syncModeStore: syncModeStore,
            migrationJournalStore: journal,
            devicePreferences: devicePreferences
        )
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        // Plan 21: ensure the AppPreferences row's device-local fields
        // have been copied into App Group UserDefaults before any
        // device-local consumer (OnboardingState, hotkey monitor, etc.)
        // reads from `DevicePreferencesStore`.
        _ = try? await preferencesPartitionMigrator.runIfNeeded()
        // One-shot CloudKit singleton convergence + catch-up reconcile for any
        // imports that arrived while the app wasn't running, then start
        // observing live remote changes.
        try? await preferencesStore.normalizeSingletons()
        await remoteChangeReconciler.processPendingHistory()
        remoteChangeReconciler.start()
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
        // blocks launch.
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
        // Plan 10: prime the iCloud account-state cache so the
        // onboarding gate has a non-default value to read.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        // ios-1: prime the pause-reason mirror so the sync-status badge and
        // PauseExplainerDialog read a real classification, not a stale nil.
        self.pauseReason = await pauseReasonClassifier.currentReason()
        startObservingAccountState()
        startObservingSyncMode()
        installCanaryLifecycleObservers()
        startObservingPauseReason()
        // Keep home-screen / Lock Screen widgets fresh: rebuild the per-filter
        // snapshot cache + reload timelines on every store change (local writes
        // AND CloudKit imports), and warm the cache once now so a freshly added
        // widget renders immediately.
        startObservingStoreChangesForWidgets()
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

    private func installCanaryLifecycleObservers() {
        let reporter = self.crashReporter
        let backup = self.localBackupCoordinator
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { try? await reporter.start() }
            // Issue #7: roll a daily snapshot if the app stays foregrounded
            // across a day boundary. No-op when one isn't due.
            Task { await backup.runSnapshotIfDue() }
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
