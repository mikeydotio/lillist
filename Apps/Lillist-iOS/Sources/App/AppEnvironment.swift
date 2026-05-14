import Foundation
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
    let smartFilterStore: SmartFilterStore
    let notificationSpecStore: NotificationSpecStore
    let snoozeRegistry: SnoozeRegistry
    let notificationScheduler: NotificationScheduler
    let notificationPermissions: NotificationPermissions
    let syncMonitor: any SyncIndicatorMonitor
    let breadcrumbs: BreadcrumbBuffer
    let crashReporter: CrashReporter
    let mailTransport: MailComposerTransport
    var crashPromptsEnabled: Bool = PreferencesStore.Prefs.crashPromptsDefault
    let buildVersion: String
    let osVersion: String
    let deviceModel: String

    private init(persistence: PersistenceController) {
        self.persistence = persistence
        self.taskStore = TaskStore(persistence: persistence)
        self.tagStore = TagStore(persistence: persistence)
        self.journalStore = JournalStore(persistence: persistence)
        self.attachmentStore = AttachmentStore(persistence: persistence)
        self.preferencesStore = PreferencesStore(persistence: persistence)
        self.smartFilterStore = SmartFilterStore(persistence: persistence)
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
        return AppEnvironment(persistence: persistence)
    }

    /// In-memory variant for tests and previews. Mirrors `make()` but uses
    /// an `.inMemory` store. Still `async throws` because
    /// `PersistenceController.init(configuration:)` is.
    static func inMemory() async throws -> AppEnvironment {
        let persistence = try await PersistenceController(configuration: .inMemory)
        return AppEnvironment(persistence: persistence)
    }

    /// One-shot async bootstrap: registers UNNotificationCategory set so
    /// snooze actions on the Lock Screen dispatch correctly.
    func bootstrap() async {
        await notificationScheduler.bootstrap()
        // Plan 9: arm canary; observer in CrashReporterHost picks up
        // any stale canary via detectAndPrepare on first paint.
        try? await crashReporter.start()
        let prefs = try? await preferencesStore.read()
        if let prefs {
            self.crashPromptsEnabled = prefs.crashPromptsEnabled
        }
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
}
