import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var isQuickCapturePresented = false

    /// Persisted sort selection for the single primary `TasksView`.
    /// Default is `.personalized` (user-controlled drag order). Stored
    /// as `rawValue`; the `Binding<TasksSort>` is computed over it so
    /// downstream views read/write a typed value.
    @AppStorage("lillist.ios.sort")
    private var sortRaw: String = TasksSort.personalized.rawValue

    private var sortBinding: Binding<TasksSort> {
        Binding(
            get: { TasksSort(rawValue: sortRaw) ?? .personalized },
            set: { sortRaw = $0.rawValue }
        )
    }

    var body: some Scene {
        WindowGroup {
            content
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.sortBinding, sortBinding)
                .task { await loadEnvironmentIfNeeded() }
        }
        .commands {
            LillistCommands(isQuickCapturePresented: $isQuickCapturePresented)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let environment {
            CrashReporterHost(
                reporter: environment.crashReporter,
                mailTransport: environment.mailTransport,
                buildVersion: environment.buildVersion,
                osVersion: environment.osVersion,
                deviceModel: environment.deviceModel,
                crashPromptsEnabled: environment.crashPromptsEnabled
            ) {
                RootShell()
                    .environment(environment)
                    .modifier(OnboardingPresentationModifier(environment: environment))
            }
        } else if let loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text("Could not load Lillist")
                    .font(.headline)
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            ProgressView("Loading Lillist…")
        }
    }

    private func loadEnvironmentIfNeeded() async {
        guard environment == nil, loadError == nil else { return }
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-store") {
                await Self.uiTestResetState()
            }
            let env = try await AppEnvironment.make()
            await env.bootstrap()
            try? await env.defaultsInstaller.installIfNeeded()
            environment = env
        } catch {
            loadError = "\(error)"
        }
    }

    /// UI-test seam: wipe on-disk store + App Group defaults and pre-mark
    /// onboarding complete in LocalOnly mode. Only invoked when the host is
    /// launched with the `--ui-test-reset-store` argument by
    /// `Lillist-iOSUITests`. Production code paths never call this.
    private static func uiTestResetState() async {
        let fm = FileManager.default
        if let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupID
        ) {
            try? fm.removeItem(at: group.appendingPathComponent("Lillist", isDirectory: true))
            try? fm.removeItem(at: group.appendingPathComponent("launch.canary"))
        }
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            try? fm.removeItem(at: appSupport.appendingPathComponent("Lillist", isDirectory: true))
        }
        if let groupDefaults = UserDefaults(suiteName: AppEnvironment.appGroupID) {
            groupDefaults.removePersistentDomain(forName: AppEnvironment.appGroupID)
            groupDefaults.synchronize()
        }
        // State-restoration keys live in UserDefaults.standard. Clear
        // both the old (pre-UI-refresh) section/path keys and the new
        // sort key so a fresh UI-test run starts clean.
        let standard = UserDefaults.standard
        standard.removeObject(forKey: "lillist.ios.section")
        standard.removeObject(forKey: "lillist.ios.filters.path")
        standard.removeObject(forKey: "lillist.ios.sort")
        await DevicePreferencesStore(appGroupID: AppEnvironment.appGroupID)
            .setHasCompletedOnboarding(true)
        await SyncModeStore(appGroupID: AppEnvironment.appGroupID).setMode(.localOnly)
        UserDefaults(suiteName: AppEnvironment.appGroupID)?.synchronize()
    }
}

/// iOS counterpart of macOS's onboarding presentation modifier.
/// Drives a one-time evaluation on first .task fire, then layers
/// either OnboardingScreen or the new ICloudUnavailableScreen on top
/// of the root tab shell. Plan 21 replaces the blocking
/// ICloudRequiredScreen — the app is never gated behind iCloud now;
/// the unavailable screen is informational and the user continues
/// into LocalOnly.
///
/// The modifier also surfaces `SyncMigrationRecoverySheet` when a
/// crashed previous migration left the `MigrationJournal` non-idle.
private struct OnboardingPresentationModifier: ViewModifier {
    let environment: AppEnvironment

    @State private var showOnboarding = false
    @State private var showICloudUnavailable = false
    @State private var didEvaluate = false
    @State private var recoveryJournal: MigrationJournal?

    func body(content: Content) -> some View {
        content
            .task {
                guard !didEvaluate else { return }
                didEvaluate = true
                await evaluate()
            }
            .fullScreenCover(isPresented: $showICloudUnavailable) {
                ICloudUnavailableScreen {
                    Task {
                        await environment.syncModeStore.setMode(.localOnly)
                        try? await environment.persistenceHost.reconfigure(to: .localOnly)
                        showICloudUnavailable = false
                        showOnboarding = true
                    }
                }
                .interactiveDismissDisabled(true)
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingScreen(
                    onboardingState: environment.onboardingState,
                    installer: environment.defaultsInstaller,
                    notificationPermissions: environment.notificationPermissions,
                    onCompleted: { showOnboarding = false }
                )
                .interactiveDismissDisabled(true)
            }
            .fullScreenCover(item: $recoveryJournal) { journal in
                SyncMigrationRecoverySheet(
                    journal: journal,
                    onRestoreFromBackup: {
                        Task {
                            let url = environment.storeURL
                                ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
                            try? await environment.migrationCoordinator.restoreFromBackup(targetURL: url)
                            recoveryJournal = nil
                        }
                    },
                    onTryAgain: {
                        try? environment.migrationJournalStore.clear()
                        recoveryJournal = nil
                    }
                )
                .interactiveDismissDisabled(true)
            }
    }

    private func evaluate() async {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-bypass-gates") {
            return
        }
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            recoveryJournal = journal
            return
        }
        let done = await environment.onboardingState.hasCompletedOnboarding()
        guard !done else { return }
        if isAvailable(environment.accountState) {
            await environment.syncModeStore.setMode(.iCloudSync)
            showOnboarding = true
        } else {
            showICloudUnavailable = true
        }
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        switch state {
        case .available: return true
        case .noAccount, .restricted, .accountChanged: return false
        }
    }
}

extension MigrationJournal: @retroactive Identifiable {
    /// Identifier the SwiftUI sheet binding needs. The journal is a
    /// singleton on disk so any non-empty identifier suffices; the
    /// failure-reason fingerprint changes between attempts which
    /// keeps the sheet re-presenting when the user retries.
    public var id: String {
        "\(state.rawValue)-\(operation?.rawValue ?? "")-\(startedAt?.timeIntervalSince1970 ?? 0)"
    }
}
