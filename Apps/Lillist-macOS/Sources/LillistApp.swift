import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment?
    @State private var loadError: String?

    var body: some Scene {
        WindowGroup("Lillist") {
            content
                .frame(minWidth: 900, minHeight: 560)
                .task { await loadEnvironmentIfNeeded() }
        }
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
                ProgressView("Loading…")
                    .frame(width: 520, height: 420)
            }
        }
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
            // Plan 10: DefaultsInstaller is also invoked from the onboarding
            // completion path; running it here too is harmless (idempotent
            // by name) and ensures returning users always have their five
            // baseline filters.
            try? await env.defaultsInstaller.installIfNeeded()
        } catch {
            loadError = "\(error)"
        }
    }
}

/// Plan 10 onboarding presentation: drives a one-time evaluation in
/// `.task`, then layers the onboarding sheet (or the iCloud-required
/// sheet if iCloud is unavailable) on top of the main window content.
/// Once the user completes onboarding the flag flips and both sheets
/// stay closed for the rest of the session.
private struct OnboardingPresentationModifier: ViewModifier {
    let environment: AppEnvironment

    @State private var showOnboarding = false
    @State private var showICloudRequired = false
    @State private var didEvaluate = false

    func body(content: Content) -> some View {
        content
            .task {
                guard !didEvaluate else { return }
                didEvaluate = true
                await evaluate()
            }
            .sheet(isPresented: $showICloudRequired) {
                ICloudRequiredView(accountMonitor: environment.accountStateMonitor)
                    .interactiveDismissDisabled(true)
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
            .onChange(of: environment.accountState) { _, new in
                // If the user fixes iCloud mid-flow, advance directly
                // into onboarding without making them relaunch.
                if showICloudRequired, isAvailable(new) {
                    showICloudRequired = false
                    showOnboarding = true
                }
            }
    }

    private func evaluate() async {
        let done = (try? await environment.onboardingState.hasCompletedOnboarding()) ?? false
        guard !done else { return }
        if isAvailable(environment.accountState) {
            showOnboarding = true
        } else {
            showICloudRequired = true
        }
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        switch state {
        case .available: return true
        case .noAccount, .restricted, .accountChanged: return false
        }
    }
}
