import SwiftUI
import LillistCore

/// Shared onboarding body content used by iOS (`OnboardingScreen`) and
/// macOS (`OnboardingSheet`). Renders the three feature bullets and a
/// permission-status row driven by the current
/// `NotificationPermissions.AuthorizationStatus`.
///
/// Per-platform pieces (the header icon size/text, the action bar
/// shape, the deep-link URL to the Settings/System Preferences screen)
/// remain in the app-target wrappers — they diverge enough that
/// sharing them would introduce more conditionals than it removes.
public struct OnboardingContent: View {
    public struct Bullet: Identifiable, Equatable {
        public let id = UUID()
        public let icon: String
        public let text: String
        public init(icon: String, text: String) {
            self.icon = icon
            self.text = text
        }
    }

    public var bullets: [Bullet]
    public var permissionStatus: NotificationPermissions.AuthorizationStatus
    public var onOpenSettings: () -> Void

    public init(
        bullets: [Bullet],
        permissionStatus: NotificationPermissions.AuthorizationStatus,
        onOpenSettings: @escaping () -> Void
    ) {
        self.bullets = bullets
        self.permissionStatus = permissionStatus
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.l) {
            ForEach(bullets) { b in
                bulletRow(icon: b.icon, text: b.text)
            }
            permissionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: LillistSpacing.m) {
            Image(systemName: icon)
                .font(LillistTypography.title3)
                .frame(width: LillistSpacing.xl + LillistSpacing.xs)
                .foregroundStyle(.tint)
            Text(text)
                .font(LillistTypography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch permissionStatus {
        case .authorized:
            Label("Notifications enabled.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            VStack(alignment: .leading, spacing: LillistSpacing.s) {
                Label("Notifications denied.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings", action: onOpenSettings)
            }
        case .notDetermined:
            EmptyView()
        }
    }
}
