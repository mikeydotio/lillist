import SwiftUI
import LillistCore
import LillistUI

@main
struct LillistApp: App {
    @State private var environment: AppEnvironment?
    @State private var loadError: String?

    var body: some Scene {
        WindowGroup {
            content
                .task { await loadEnvironmentIfNeeded() }
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
            try? await DefaultSmartFiltersInstaller.installIfNeeded(
                store: env.smartFilterStore
            )
            // Notification authorization is handled by NotificationPermissions
            // — best-effort here; UI continues to function if denied.
            _ = await env.notificationPermissions.requestAuthorization()
            environment = env
        } catch {
            loadError = "\(error)"
        }
    }
}
