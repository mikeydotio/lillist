import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var isQuickCapturePresented = false
    @State private var isSearchPresented = false

    /// Persisted selected tab. Plan: state-restoration.
    /// Stored as the raw enum value; `Binding<iPadSection?>` is computed
    /// over it so the `LillistCommands` and shell bindings keep their
    /// existing nil-safe shape. Multi-window iPad shares this value —
    /// acceptable for v1 (Mikey hasn't asked for per-window).
    @AppStorage("lillist.ios.section")
    private var selectedSectionRaw: String = iPadSection.today.rawValue

    /// Persisted Filters-tab `NavigationPath`. Stored as
    /// JSON-encoded `NavigationPath.CodableRepresentation`. Empty
    /// `Data` = "no stored path" (start at the Filters root).
    /// Plan: state-restoration.
    @AppStorage("lillist.ios.filters.path")
    private var filtersPathData: Data = Data()

    /// Live `NavigationPath` mirrored to `filtersPathData` via
    /// `.onChange`. Initial decode runs once on first scene `.task`.
    @State private var filtersPath = NavigationPath()
    @State private var didRestoreFiltersPath = false

    private var selectedSectionBinding: Binding<iPadSection?> {
        Binding(
            get: { iPadSection(rawValue: selectedSectionRaw) ?? .today },
            set: { selectedSectionRaw = ($0 ?? .today).rawValue }
        )
    }

    var body: some Scene {
        WindowGroup {
            content
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.isSearchPresentedBinding, $isSearchPresented)
                .environment(\.selectedSectionBinding, selectedSectionBinding)
                .environment(\.filtersPathBinding, $filtersPath)
                .task {
                    await loadEnvironmentIfNeeded()
                    restoreFiltersPathIfNeeded()
                }
                .onChange(of: filtersPath) { _, newValue in
                    persistFiltersPath(newValue)
                }
        }
        .commands {
            LillistCommands(
                isQuickCapturePresented: $isQuickCapturePresented,
                isSearchPresented: $isSearchPresented,
                selectedSection: selectedSectionBinding
            )
        }
    }

    /// Decode the persisted path exactly once per scene cold-start.
    /// Guarded by `didRestoreFiltersPath` so subsequent `.task` fires
    /// (e.g. after backgrounding) don't clobber the live path with
    /// the stale on-disk snapshot.
    private func restoreFiltersPathIfNeeded() {
        guard !didRestoreFiltersPath else { return }
        didRestoreFiltersPath = true
        guard !filtersPathData.isEmpty,
              let representation = try? JSONDecoder().decode(
                  NavigationPath.CodableRepresentation.self,
                  from: filtersPathData
              ) else { return }
        filtersPath = NavigationPath(representation)
    }

    /// Encode the live path into `@AppStorage` so the next launch
    /// restores it. Skipped before the initial decode runs to avoid
    /// blanking the stored path on cold-start.
    private func persistFiltersPath(_ path: NavigationPath) {
        guard didRestoreFiltersPath else { return }
        guard let representation = path.codable,
              let data = try? JSONEncoder().encode(representation) else {
            filtersPathData = Data()
            return
        }
        filtersPathData = data
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
            // UI-test seam (Plan: RCA — iOS new-task flow). The wipe arg
            // is independent from the gate-bypass arg so a relaunch in
            // the same test can skip onboarding/crash gates *without*
            // wiping the data we're trying to verify persisted.
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-store") {
                await Self.uiTestResetState()
            }
            let env = try await AppEnvironment.make()
            await env.bootstrap()
            // Plan 10: invoke the defaults installer once on every cold
            // launch. The onboarding completion path runs the same
            // installer; running here is a safety net for returning
            // users who already passed onboarding before this code
            // landed, and is harmless on subsequent launches (idempotent
            // by name).
            try? await env.defaultsInstaller.installIfNeeded()
            // Plan 10 deviation note: Plan 8's
            // `await env.notificationPermissions.requestAuthorization()`
            // unconditional first-launch prompt is removed. Plan 10's
            // onboarding flow now owns the prompt — first-launch users
            // see the explanation in OnboardingScreen and tap "Set up
            // notifications" to consent. Returning users who already
            // dismissed onboarding never see a re-prompt.
            environment = env
        } catch {
            loadError = "\(error)"
        }
    }

    /// UI-test seam: wipe on-disk store + App Group defaults and pre-mark
    /// onboarding complete in LocalOnly mode. Only invoked when the host is
    /// launched with the `--ui-test-reset-store` argument by
    /// `Lillist-iOSUITests`. Production code paths never call this.
    ///
    /// Order matters: wipe the file-backed stores, wipe the App Group
    /// defaults, force the wipe to flush (`synchronize`), then write the
    /// bypass values. Without the synchronize the wipe can be buffered
    /// and clobber the bypass writes, leaving the onboarding flag false
    /// and the modifier showing the Welcome screen.
    private static func uiTestResetState() async {
        let fm = FileManager.default
        if let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupID
        ) {
            try? fm.removeItem(at: group.appendingPathComponent("Lillist", isDirectory: true))
            // The crash-report canary lives at the App Group root (not
            // inside `Lillist/`). A killed test run leaves it on disk and
            // the next launch's CrashReporterHost pops the "What will be
            // sent" sheet over the app, blocking the UI test.
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
        // State-restoration keys live in UserDefaults.standard (not the
        // App Group). Clear them so a fresh UI-test run starts on the
        // Today tab with no filters drill-in.
        let standard = UserDefaults.standard
        standard.removeObject(forKey: "lillist.ios.section")
        standard.removeObject(forKey: "lillist.ios.filters.path")
        // Pre-mark onboarding complete + switch to LocalOnly so the test
        // bypasses OnboardingPresentationModifier's `fullScreenCover`s.
        await DevicePreferencesStore(appGroupID: AppEnvironment.appGroupID)
            .setHasCompletedOnboarding(true)
        await SyncModeStore(appGroupID: AppEnvironment.appGroupID).setMode(.localOnly)
        // Belt-and-suspenders: belt and force-flush the suite again after
        // the bypass writes so the next `UserDefaults(suiteName:)` read
        // sees them. UserDefaults cross-suite caching has historically
        // bitten this exact pattern.
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
                        // Plan 21: a fresh install without iCloud
                        // available → default to LocalOnly so the
                        // user doesn't see a paused indicator on
                        // launch.
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
                        // Retry path: just clear the journal so the
                        // user can re-attempt from Settings.
                        try? environment.migrationJournalStore.clear()
                        recoveryJournal = nil
                    }
                )
                .interactiveDismissDisabled(true)
            }
    }

    private func evaluate() async {
        // UI-test seam: explicit, in-process bypass that doesn't depend on
        // UserDefaults timing across actor boundaries. The synchronize-based
        // approach in `LillistApp.uiTestResetState` was racing this method.
        // The gate-bypass arg is independent of the wipe arg so a relaunch
        // in the same test (verifying persistence) can skip onboarding
        // without wiping the data being verified.
        if ProcessInfo.processInfo.arguments.contains("--ui-test-bypass-gates") {
            return
        }
        // Plan 21: recovery sheet supersedes onboarding when a crashed
        // migration is on disk.
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            recoveryJournal = journal
            return
        }
        let done = await environment.onboardingState.hasCompletedOnboarding()
        guard !done else { return }
        if isAvailable(environment.accountState) {
            // iCloud available + first launch → silently keep
            // iCloudSync as the chosen mode, advance to onboarding.
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
