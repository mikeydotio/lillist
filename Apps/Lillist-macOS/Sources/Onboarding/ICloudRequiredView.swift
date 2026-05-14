import SwiftUI
import AppKit
import LillistCore

/// Full-window blocker shown when iCloud is unavailable during
/// onboarding (design Section 8, "iCloud account states"). The user
/// can dismiss the screen via "Try again" (re-runs an account-status
/// refresh through the injected monitor) or "Open System Settings"
/// (deep-links into the Apple-ID pane). Onboarding cannot proceed past
/// this screen until the account becomes available.
struct ICloudRequiredView: View {
    let accountMonitor: AccountStateMonitor

    @State private var isRechecking = false
    @State private var lastError: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.red)
            Text("iCloud is required")
                .font(.title)
                .bold()
            Text("Lillist syncs your tasks via your private iCloud database. Please sign into iCloud in System Settings and try again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let lastError {
                Text(lastError)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 420)
            }
            HStack(spacing: 12) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button {
                    Task { await recheck() }
                } label: {
                    if isRechecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Try again")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(width: 520, height: 360)
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
