import SwiftUI
import LillistCore
import LillistUI

/// First-launch onboarding screen for iOS (full-screen cover).
///
/// One screen with the same content matrix as the macOS sheet (Plan 10
/// Task 6): welcome header, three bullets, permission status, two
/// primary actions, and a "Skip for now" link. The Quick Capture
/// bullet swaps to the iOS-appropriate Lock Screen Shortcut + floating
/// + button affordances (design Section 7).
///
/// Same explicit-constructor-injection pattern as the macOS variant —
/// the cover's presenting view reads `@Environment(AppEnvironment.self)`
/// and forwards just the four dependencies that matter.
struct OnboardingScreen: View {
    let onboardingState: OnboardingState
    let installer: DefaultsInstaller
    let notificationPermissions: NotificationPermissions
    let onCompleted: () -> Void

    @State private var permissionStatus: NotificationPermissions.AuthorizationStatus = .notDetermined
    @State private var isRequesting = false
    @State private var isCompleting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    OnboardingContent(
                        bullets: Self.iOSBullets,
                        permissionStatus: permissionStatus,
                        onOpenSettings: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .padding(24)
            }
            actionBar
        }
        .task { permissionStatus = await notificationPermissions.currentStatus() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(LillistTypography.largeTitle.weight(.light))
                .foregroundStyle(.tint)
            Text("Welcome to Lillist")
                .font(.largeTitle.bold())
            Text("Lists, tags, and reminders — synced to your iCloud.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private static let iOSBullets: [OnboardingContent.Bullet] = [
        .init(icon: "icloud", text: "iCloud sync is required. Your data lives in your private CloudKit database."),
        .init(icon: "bell", text: "Notification permission powers reminders for tasks with dates."),
        .init(icon: "plus.circle", text: "Use the Lock Screen Shortcut or the floating + button to capture anywhere.")
    ]

    private var actionBar: some View {
        VStack(spacing: 12) {
            Button {
                Task { await requestPermission() }
            } label: {
                Text(isRequesting ? "Requesting…" : "Set up notifications")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(isRequesting || permissionStatus != .notDetermined)

            Button {
                Task { await complete() }
            } label: {
                Text(isCompleting ? "Finishing…" : "Get started")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCompleting)

            Button("Skip for now") {
                Task { await complete() }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .accessibleMaterial(
            .bar,
            fallback: Color(uiColor: .systemBackground)
        )
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
            await onboardingState.markCompleted()
            onCompleted()
        } catch {
            let message = String(
                localized: "Couldn't finish onboarding: \(error.localizedDescription)"
            )
            errorMessage = message
            AccessibilityAnnouncements.post(message, priority: .high)
        }
    }
}
