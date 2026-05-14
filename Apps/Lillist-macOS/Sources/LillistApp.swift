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
    }

    @ViewBuilder
    private var content: some View {
        if let environment {
            RootSplitView()
                .environment(environment)
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
            try? await DefaultSmartFiltersInstaller.installIfNeeded(
                store: env.smartFilterStore
            )
        } catch {
            loadError = "\(error)"
        }
    }
}
