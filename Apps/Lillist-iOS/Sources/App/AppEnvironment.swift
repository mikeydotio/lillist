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
    let persistence: PersistenceController
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

    private init(persistence: PersistenceController, devicePreferences: DevicePreferencesStore) {
        self.persistence = persistence
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
        self.accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer.default())
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
    }

    /// App Group identifier shared between the main app, Share Extension,
    /// and Shortcuts (App Intents) extension. Matches the entitlement on
    /// every target.
    static let appGroupID = "group.io.mikeydotio.Lillist"

    /// Async-friendly constructor. Loads the Core Data store inside the
    /// App Group's shared container so the Share Extension and App
    /// Intents extension see the same data.
    static func make() async throws -> AppEnvironment {
        let config: StoreConfiguration
        if let group = StoreConfiguration.appGroupOnDisk(groupID: appGroupID) {
            config = group
        } else {
            config = try StoreConfiguration.defaultOnDisk
        }
        let persistence = try await PersistenceController(configuration: config)
        let devicePreferences = DevicePreferencesStore(appGroupID: appGroupID)
        return AppEnvironment(persistence: persistence, devicePreferences: devicePreferences)
    }

    /// In-memory variant for tests and previews. Mirrors `make()` but uses
    /// an `.inMemory` store. Still `async throws` because
    /// `PersistenceController.init(configuration:)` is.
    static func inMemory() async throws -> AppEnvironment {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let suite = "AppEnvironment.inMemory-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let devicePreferences = DevicePreferencesStore(suiteName: suite)
        return AppEnvironment(persistence: persistence, devicePreferences: devicePreferences)
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
        // Plan 9: arm canary; observer in CrashReporterHost picks up
        // any stale canary via detectAndPrepare on first paint.
        try? await crashReporter.start()
        self.crashPromptsEnabled = await devicePreferences.crashPromptsEnabled()
        // Plan 10: prime the iCloud account-state cache so the
        // onboarding gate has a non-default value to read.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        startObservingAccountState()
        // Observe willTerminate so we delete the canary on clean exit.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let reporter = self?.crashReporter else { return }
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
}
