import SwiftUI
import LillistCore
import LillistUI

/// Full-screen blocker shown when iCloud is unavailable during
/// onboarding on iOS (design Section 8). The user can deep-link into
/// Settings to sign in or retry the account-status check.
struct ICloudRequiredScreen: View {
    let accountMonitor: AccountStateMonitor

    @State private var isRechecking = false
    @State private var lastError: String?

    var body: some View {
        VStack(spacing: LillistSpacing.l) {
            ICloudRequiredContent(lastError: lastError)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)

            Button {
                Task { await recheck() }
            } label: {
                if isRechecking {
                    ProgressView()
                } else {
                    Text("Try again").frame(maxWidth: 180)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(LillistSpacing.xl + LillistSpacing.s)
    }

    private func recheck() async {
        isRechecking = true
        lastError = nil
        defer { isRechecking = false }
        do {
            try await accountMonitor.refresh()
        } catch {
            lastError = "iCloud check failed: \(error.localizedDescription)"
        }
    }
}
