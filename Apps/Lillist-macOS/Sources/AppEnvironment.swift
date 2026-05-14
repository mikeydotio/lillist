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
    let persistence: PersistenceController
    let taskStore: TaskStore
    let tagStore: TagStore
    let journalStore: JournalStore
    let preferencesStore: PreferencesStore
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
    var crashPromptsEnabled: Bool = PreferencesStore.Prefs.crashPromptsDefault
    /// Plan 10: latest known iCloud account state, mirrored off the
    /// `AccountStateMonitor` actor so SwiftUI views can react via
    /// `@Observable`-based observation.
    var accountState: iCloudAccountState = .noAccount
    let buildVersion: String
    let osVersion: String
    let deviceModel: String

    private init(persistence: PersistenceController) {
        self.persistence = persistence
        self.taskStore = TaskStore(persistence: persistence)
        self.tagStore = TagStore(persistence: persistence)
        self.journalStore = JournalStore(persistence: persistence)
        let preferencesStore = PreferencesStore(persistence: persistence)
        self.preferencesStore = preferencesStore
        let smartFilterStore = SmartFilterStore(persistence: persistence)
        self.smartFilterStore = smartFilterStore
        self.onboardingState = OnboardingState(preferences: preferencesStore)
        self.defaultsInstaller = DefaultsInstaller(filters: smartFilterStore)
        self.accountStateMonitor = AccountStateMonitor(
            provider: CloudKitAccountStatusProvider(container: CKContainer.default())
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
    }

    /// Async-friendly constructor. Loads the Core Data store and wires up
    /// every store / scheduler used by the SwiftUI hierarchy.
    static func make() async throws -> AppEnvironment {
        let persistence = try await PersistenceController(configuration: .defaultOnDisk)
        let env = AppEnvironment(persistence: persistence)
        return env
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        await notificationScheduler.bootstrap()
        // Plan 9: start the canary for *this* run. detectAndPrepare()
        // (called by CrashReporterHost on first render) will read any
        // stale canary the prior crashed process left and then re-arm.
        // We call start() defensively in case the host never gets a
        // chance to render (e.g. some failure between env.make() and
        // first paint) — the cost of an extra fresh canary write is nil.
        try? await crashReporter.start()
        // Hydrate crashPromptsEnabled from the user's preferences.
        let prefs = try? await preferencesStore.read()
        if let prefs {
            self.crashPromptsEnabled = prefs.crashPromptsEnabled
        }
        // Plan 10: prime the iCloud account-state cache so the onboarding
        // gate has a non-default value to read. Errors fall through; the
        // gate handles `.noAccount` as the "iCloud unavailable" branch.
        try? await accountStateMonitor.refresh()
        self.accountState = await accountStateMonitor.currentState
        startObservingAccountState()
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
