import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var isQuickCapturePresented = false
    @State private var selectedSection: iPadSection? = .today

    var body: some Scene {
        WindowGroup {
            content
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.selectedSectionBinding, $selectedSection)
                .task { await loadEnvironmentIfNeeded() }
        }
        .commands {
            LillistCommands(
                isQuickCapturePresented: $isQuickCapturePresented,
                selectedSection: $selectedSection
            )
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
}

/// iOS counterpart of macOS's onboarding presentation modifier.
/// Drives a one-time evaluation on first .task fire, then layers
/// either OnboardingScreen or ICloudRequiredScreen on top of the
/// root tab shell via full-screen covers.
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
            .fullScreenCover(isPresented: $showICloudRequired) {
                ICloudRequiredScreen(accountMonitor: environment.accountStateMonitor)
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
            .onChange(of: environment.accountState) { _, new in
                if showICloudRequired, isAvailable(new) {
                    showICloudRequired = false
                    showOnboarding = true
                }
            }
    }

    private func evaluate() async {
        let done = await environment.onboardingState.hasCompletedOnboarding()
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
