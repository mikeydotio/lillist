import SwiftUI
import AppKit
import LillistCore
import LillistUI

/// First-launch onboarding sheet for macOS.
///
/// One screen with: app name + tagline, three bullets (iCloud,
/// notifications, global hotkey), two primary actions ("Set up
/// notifications" / "Get started"), and a "Skip for now" link.
///
/// See design Section 7 ("Onboarding"). The sheet is non-dismissable
/// via interactive gesture (`.interactiveDismissDisabled(true)` is
/// applied at the presentation site) — the user must explicitly
/// proceed via one of the three buttons, which all complete onboarding.
///
/// Plan 10 deviation: the panel rejected the plan's `AppServices.shared`
/// pattern in favor of explicit constructor injection. The host view
/// passes the four LillistCore dependencies it needs; the sheet does
/// not reach into `@Environment` because sheet presentation creates a
/// fresh environment chain and silent lookups would crash on first paint.
struct OnboardingSheet: View {
    let onboardingState: OnboardingState
    let installer: DefaultsInstaller
    let notificationPermissions: NotificationPermissions
    /// Invoked from any of the three completion paths after the
    /// onboarding flag has been set. The host uses this to dismiss the
    /// sheet — relying on `@Environment(\.dismiss)` inside the sheet
    /// also works on macOS 15, but explicit callbacks are simpler to
    /// test.
    let onCompleted: () -> Void

    @State private var permissionStatus: NotificationPermissions.AuthorizationStatus = .notDetermined
    @State private var isRequesting = false
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 24) {
            header
            bullets
            permissionStatusRow
            buttons
            skipLink
        }
        .padding(40)
        .frame(width: 520)
        .task {
            permissionStatus = await notificationPermissions.currentStatus()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(LillistTypography.largeTitle.weight(.light))
                .foregroundStyle(.tint)
            Text("Welcome to Lillist")
                .font(LillistTypography.title2.weight(.semibold))
            Text("A pure-nesting task manager. Everything is a task.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 14) {
            bullet(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database.")
            bullet(icon: "bell", text: "Notification permission powers reminders for tasks with dates.")
            bullet(icon: "keyboard", text: "Press \u{2303}\u{2325}Space anywhere for Quick Capture.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(.tint)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionStatusRow: some View {
        switch permissionStatus {
        case .authorized:
            Label("Notifications enabled.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: 6) {
                Label("Notifications denied.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
        case .notDetermined:
            EmptyView()
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await requestPermission() }
            } label: {
                if isRequesting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Set up notifications")
                }
            }
            .disabled(isRequesting || permissionStatus != .notDetermined)

            Button {
                Task { await complete() }
            } label: {
                if isCompleting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Get started")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isCompleting)
        }
    }

    private var skipLink: some View {
        Button("Skip for now") {
            Task { await complete() }
        }
        .buttonStyle(.link)
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }
        permissionStatus = await notificationPermissions.requestAuthorization()
    }

    private func complete() async {
        isCompleting = true
        defer { isCompleting = false }
        do {
            try await installer.installIfNeeded()
            try await onboardingState.markCompleted()
            onCompleted()
        } catch {
            // Surface to the user — non-fatal; they can retry.
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
