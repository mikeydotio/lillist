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
    let seriesStore: SeriesStore
    let smartFilterStore: SmartFilterStore
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    let notificationPermissions: NotificationPermissions
    let accountStateMonitor: AccountStateMonitor
    let onboardingState: OnboardingState
    let defaultsInstaller: DefaultsInstaller
    let syncMonitor: any SyncIndicatorMonitor
    let breadcrumbs: BreadcrumbBuffer
    let crashReporter: CrashReporter
    let mailTransport: MailComposerTransport
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
        self.onboardingState = OnboardingState(devicePreferences: devicePreferences)
        self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)
        let ckContainerID = StoreConfiguration.defaultCloudKitContainerIdentifier
        self.accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer(identifier: ckContainerID))
        )
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

        // Plan 2 stub — once the CloudKit-backed monitor is bridged into
        // the UI's SyncIndicatorMonitor protocol, swap this for the live one.
        self.syncMonitor = IdleSyncIndicatorMonitor()

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
            syncModeStore: syncModeStore,
            breadcrumbs: breadcrumbs,
            cloudKitContainerIdentifier: ckContainerID,
            localStoreRowCount: localStoreRowCount
        )
    }

    /// App Group identifier shared between the main app, Share Extension,
    /// and Shortcuts (App Intents) extension. Matches the entitlement on
    /// every target.
    static let appGroupID = "group.io.mikeydotio.Lillist"

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
        await notificationScheduler.bootstrap()
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
        startObservingAccountState()
        startObservingSyncMode()
        installCanaryLifecycleObservers()
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
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { try? await reporter.start() }
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
}
