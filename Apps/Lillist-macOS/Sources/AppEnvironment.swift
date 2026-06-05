import Foundation
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
    let syncModeStore: SyncModeStore
    let migrationJournalStore: any MigrationJournalStore
    let migrationCoordinator: MigrationCoordinator
    let pauseReasonClassifier: PauseReasonClassifier
    var currentSyncMode: SyncMode = .default
    /// Plan 21: latest classification by `PauseReasonClassifier`.
    var pauseReason: PauseReason?
    let taskStore: TaskStore
    let tagStore: TagStore
    let journalStore: JournalStore
    let seriesStore: SeriesStore
    let preferencesStore: PreferencesStore
    let devicePreferences: DevicePreferencesStore
    let preferencesPartitionMigrator: AppPreferencesPartitionMigrator
    let smartFilterStore: SmartFilterStore
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    let notificationPermissions: NotificationPermissions
    let accountStateMonitor: AccountStateMonitor
    let onboardingState: OnboardingState
    let defaultsInstaller: DefaultsInstaller
    /// Persist-6: hard-deletes trash older than the retention window.
    /// Run opportunistically at launch (`bootstrap()`). Parity with iOS.
    let autoPurgeJob: AutoPurgeJob
    /// Plan 11 Task 18: the global hotkey monitor lives on the
    /// environment (alongside the other singletons) so the Quick
    /// Capture preferences pane can call `reregister(combo:)` directly
    /// when the user saves a new combo. `AppDelegate.bootstrap()`
    /// configures `onHotkey` and calls `install()`.
    let hotkeyMonitor: GlobalHotkeyMonitor
    let syncMonitor: any SyncIndicatorMonitor
    let breadcrumbs: BreadcrumbBuffer
    let crashReporter: CrashReporter
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
        initialHotkeyCombo: String = GlobalHotkeyMonitor.defaultCombo
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
            provider: CloudKitAccountStatusProvider(container: CKContainer(identifier: ckContainerID))
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

        // Plan 9: wire each store's breadcrumb sink to the shared buffer
        // *after* it's created below. Done in two passes because the
        // BreadcrumbBuffer field is declared later in this init.

        // Plan 2 stub — once Plan 2 ships, swap in a CloudKitSyncStatusAdapter
        // that bridges LillistCore.SyncStatusMonitor's statusStream to the
        // SyncIndicatorMonitor protocol shape.
        self.syncMonitor = IdleSyncIndicatorMonitor()

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

        // Plan 21: assemble the migration machinery + classifier.
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
    }

    /// App Group identifier shared with the iOS app, extensions, and CLI.
    static let appGroupID = "group.io.mikeydotio.Lillist"

    /// Async-friendly constructor. Loads the Core Data store and wires up
    /// every store / scheduler used by the SwiftUI hierarchy.
    static func make() async throws -> AppEnvironment {
        let syncModeStore = SyncModeStore(appGroupID: appGroupID)
        let initialMode = await syncModeStore.currentMode()
        let baseConfig = try StoreConfiguration.defaultOnDisk.withSyncMode(initialMode)
        let persistence = try await PersistenceController(configuration: baseConfig)
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
            initialSyncMode: initialMode,
            syncModeStore: syncModeStore,
            migrationJournalStore: journal,
            devicePreferences: devicePreferences,
            initialHotkeyCombo: combo
        )
        return env
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        // Plan 21: copy the AppPreferences row's device-local fields
        // forward into App Group UserDefaults if we haven't already.
        // Idempotent; subsequent launches no-op.
        _ = try? await preferencesPartitionMigrator.runIfNeeded()
        await notificationScheduler.bootstrap()
        // Persist-6: opportunistically clear expired trash at launch.
        _ = try? await autoPurgeJob.run()
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
        // Plan 10: prime the iCloud account-state cache so the onboarding
        // gate has a non-default value to read. Errors fall through; the
        // gate handles `.noAccount` as the "iCloud unavailable" branch.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        // ios-1 parity: prime the pause-reason mirror the Preferences sync
        // pane reads, so the macOS classifier stops being dead too.
        self.pauseReason = await pauseReasonClassifier.currentReason()
        startObservingAccountState()
        startObservingSyncMode()
        startObservingPauseReason()
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
