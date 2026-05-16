import SwiftUI
import AppKit
import LillistCore
import LillistUI

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
        VStack(spacing: LillistSpacing.l) {
            ICloudRequiredContent(lastError: lastError)

            HStack(spacing: LillistSpacing.m) {
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
        .padding(LillistSpacing.xxl)
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
