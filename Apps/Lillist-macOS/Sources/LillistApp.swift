import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var statusBarItemVisible = true

    init() {
        // Register the bundled Plus Jakarta Sans faces before the first
        // frame renders, so LillistTypography never falls back to system
        // fonts for a flash. (Registration is also lazy via the
        // typography factory; this call just front-loads it.)
        LillistFonts.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup("Lillist", id: "main") {
            content
                .frame(minWidth: 900, minHeight: 560)
                .task { await loadEnvironmentIfNeeded() }
                .modifier(MainWindowReopener())
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentSize)
        .commands {
            if let environment {
                LillistCommands(environment: environment)
            }
        }

        // Plan 10: Preferences scene. SwiftUI's `Settings { ... }`
        // produces the standard ⌘, window with native tab styling.
        Settings {
            if let environment {
                PreferencesWindow()
                    .environment(environment)
            } else {
                // Plan 15 Task 26: the loaded panes self-size via
                // `.fixedSize()`, so the placeholder also self-sizes
                // (just paddding around the spinner). Don't lock to
                // the old 520×420 — that was the only artifact pinning
                // a square window even when only one tab was tall.
                ProgressView("Loading…")
                    .padding()
            }
        }

        // Plan 15 Task 9: SwiftUI MenuBarExtra scene replaces the
        // AppKit-bridge StatusBarController. `isInserted:` is driven
        // by `PreferencesStore.statusBarItemVisible` and primed in
        // `loadEnvironmentIfNeeded()`; flipping the toggle in
        // Preferences adds/removes the scene at runtime. The scene
        // is declared unconditionally (SceneBuilder's type-checker
        // handles optional Scenes poorly); MenuBarExtraScene itself
        // takes an optional `AppEnvironment?` and renders a
        // placeholder while it's still loading.
        MenuBarExtraScene(
            isInserted: $statusBarItemVisible,
            environment: environment,
            onQuickCapture: triggerQuickCapture
        )
    }

    private func triggerQuickCapture() {
        appDelegate.quickCapturePanel?.toggle()
    }

    @ViewBuilder
    private var content: some View {
        if let environment {
            CrashReporterHost(
                reporter: environment.crashReporter,
                buildVersion: environment.buildVersion,
                osVersion: environment.osVersion,
                deviceModel: environment.deviceModel,
                crashPromptsEnabled: environment.crashPromptsEnabled
            ) {
                RootSplitView()
                    .environment(environment)
                    .modifier(OnboardingPresentationModifier(environment: environment))
            }
        } else if let loadError {
            EmptyStateView(
                title: "Could not load Lillist",
                message: loadError,
                systemImage: "exclamationmark.triangle"
            )
        } else {
            ProgressView("Loading Lillist…")
        }
    }

    private func loadEnvironmentIfNeeded() async {
        guard environment == nil, loadError == nil else { return }
        do {
            let env = try await AppEnvironment.make()
            environment = env
            appDelegate.environment = env
            appDelegate.bootstrap()
            await env.bootstrap()
            // Plan 19 Task 10: sole install path — runs on every launch
            // (idempotent by name). OnboardingSheet used to call this too
            // but that was redundant: a user who quits mid-onboarding
            // still gets defaults the next launch through this code path.
            try? await env.defaultsInstaller.installIfNeeded()
            // Plan 15 Task 9: prime the menu-bar visibility binding from
            // user prefs so the MenuBarExtra scene inserts (or not) on
            // first launch matching the saved setting.
            if let prefs = try? await env.preferencesStore.read() {
                statusBarItemVisible = prefs.statusBarItemVisible
            }
        } catch {
            loadError = "\(error)"
        }
    }
}

/// Plan 21 onboarding presentation (macOS): drives a one-time
/// evaluation in `.task`, then layers either the onboarding sheet
/// or the cross-platform `ICloudUnavailableScreen` on top of the
/// main window content. Replaces the old blocking
/// `ICloudRequiredView` — the app is no longer gated behind iCloud.
///
/// Also surfaces `SyncMigrationRecoverySheet` if a crashed previous
/// migration left the journal non-idle.
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
            .sheet(isPresented: $showICloudUnavailable) {
                ICloudUnavailableScreen {
                    Task {
                        await environment.syncModeStore.setMode(.localOnly)
                        try? await environment.persistenceHost.reconfigure(to: .localOnly)
                        showICloudUnavailable = false
                        showOnboarding = true
                    }
                }
                .interactiveDismissDisabled(true)
                .frame(width: 520, height: 380)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet(
                    onboardingState: environment.onboardingState,
                    installer: environment.defaultsInstaller,
                    notificationPermissions: environment.notificationPermissions,
                    onCompleted: { showOnboarding = false }
                )
                .interactiveDismissDisabled(true)
            }
            .sheet(item: $recoveryJournal) { journal in
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
                .frame(width: 520, height: 380)
            }
    }

    private func evaluate() async {
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            // Only offer recovery for a *stale* (crashed) migration. A
            // fresh in-flight journal belongs to a migration that may still
            // be completing in another process/launch; surfacing recovery
            // would race it. The MigrationGate keeps blocking new work
            // either way.
            if journal.isStale() {
                recoveryJournal = journal
            }
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
    public var id: String {
        "\(state.rawValue)-\(operation?.rawValue ?? "")-\(startedAt?.timeIntervalSince1970 ?? 0)"
    }
}

/// Plan 19 Task 12: re-spawn the main window when the user closes the
/// only window with `⌘W` and then clicks the Dock icon (or hits the
/// "Show Main Window" item in the menu-bar popover). Both paths post
/// `.lillistReopenMainWindow`; this modifier grabs `openWindow` from
/// the SwiftUI environment and reopens the `WindowGroup(id: "main")`.
private struct MainWindowReopener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .lillistReopenMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}
