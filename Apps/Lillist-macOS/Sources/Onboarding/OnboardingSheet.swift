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
            OnboardingContent(
                bullets: Self.macOSBullets,
                permissionStatus: permissionStatus,
                onOpenSettings: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
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
        // The onboarding hero is a sanctioned full-rainbow moment —
        // mirrors the iOS wrapper; strings stay verbatim-aligned.
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(LillistTypography.largeTitle.weight(.medium))
                .foregroundStyle(RainbowGradient.vertical)
            Text("Welcome to Lillist")
                .font(LillistTypography.title2)
                .foregroundStyle(RainbowGradient.horizontal)
            Text("Lists, tags, and reminders — synced to your iCloud.")
                .font(LillistTypography.title3)
                .foregroundStyle(LillistColor.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(DotGridBackdrop())
    }

    private static let macOSBullets: [OnboardingContent.Bullet] = [
        .init(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database."),
        .init(icon: "bell", text: "Notification permission powers reminders for tasks with dates."),
        .init(icon: "keyboard", text: "Press \u{2303}\u{2325}Space anywhere for Quick Capture.")
    ]

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
            .buttonStyle(.rainbow(.secondary, size: .sm))
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
            // Hero CTA — the sanctioned full-gradient success moment.
            .buttonStyle(.rainbow(.rainbow, size: .sm))
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
        // Plan 19 Task 10: `installer.installIfNeeded()` was previously
        // called here too, but every launch already runs it via
        // `LillistApp.loadEnvironmentIfNeeded()`. The onboarding-side
        // call was structurally redundant — a user who quits
        // mid-onboarding still gets defaults the next launch through
        // the App-startup path. The `installer` parameter stays on the
        // init for type-shape parity with iOS `OnboardingScreen`.
        _ = installer
        await onboardingState.markCompleted()
        onCompleted()
    }
}
