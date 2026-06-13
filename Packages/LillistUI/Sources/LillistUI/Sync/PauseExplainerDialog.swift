import SwiftUI
import LillistCore

/// Sheet/dialog explaining why iCloud sync is paused.
///
/// Plan 21: the indicator (cloud-with-slash) is tappable across iOS
/// and macOS. The tap invokes this dialog with the active
/// `PauseReason`. Copy is sourced verbatim from the design spec's
/// truth table and matches across platforms.
///
/// The view is pure presentation — no env-coupled lifecycle. Hosts
/// pass three closures: `onOpenSettings` opens the appropriate
/// system Settings (UIApplication.shared.open on iOS, NSWorkspace
/// on macOS); `onDisableSync` lets the user fall back to LocalOnly
/// from inside the dialog (only surfaced for `.accountChanged`);
/// `onDismiss` tears down the presenting sheet.
public struct PauseExplainerDialog: View {
    public let reason: PauseReason
    public let onOpenSettings: () -> Void
    public let onDisableSync: () -> Void
    public let onDismiss: () -> Void

    public init(
        reason: PauseReason,
        onOpenSettings: @escaping () -> Void,
        onDisableSync: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void
    ) {
        self.reason = reason
        self.onOpenSettings = onOpenSettings
        self.onDisableSync = onDisableSync
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(body(for: reason))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                if let primary = primaryAction {
                    Button(primary, action: onOpenSettings)
                        .buttonStyle(.borderedProminent)
                }
                if reason == .accountChanged {
                    Button("Disable Sync", action: onDisableSync)
                        .buttonStyle(.bordered)
                }
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 420)
    }

    private var title: String {
        switch reason {
        case .noAccount: return String(localized: "iCloud isn't signed in", bundle: .module)
        case .restricted: return String(localized: "iCloud is restricted", bundle: .module)
        case .accountChanged: return String(localized: "iCloud account changed", bundle: .module)
        case .noNetwork: return String(localized: "No internet connection", bundle: .module)
        case .iCloudDriveDisabled: return String(localized: "iCloud Drive is off", bundle: .module)
        case .unknown: return String(localized: "Sync is paused", bundle: .module)
        }
    }

    private func body(for reason: PauseReason) -> String {
        switch reason {
        case .noAccount:
            return String(localized: "iCloud isn't signed in on this device.", bundle: .module)
        case .restricted:
            return String(localized: "iCloud isn't currently available on this device. Check Settings to see why.", bundle: .module)
        case .accountChanged:
            return String(localized: "Your iCloud account changed since the last sync. Sign back into the original account, or migrate your data.", bundle: .module)
        case .noNetwork:
            return String(localized: "No internet connection. Sync will resume automatically.", bundle: .module)
        case .iCloudDriveDisabled:
            return String(localized: "iCloud Drive is turned off for Lillist.", bundle: .module)
        case .unknown:
            return String(localized: "Sync is paused. Check iCloud settings and your internet connection.", bundle: .module)
        }
    }

    private var primaryAction: String? {
        switch reason {
        case .noAccount, .restricted, .accountChanged, .iCloudDriveDisabled, .unknown:
            return String(localized: "Open Settings", bundle: .module)
        case .noNetwork:
            return nil
        }
    }
}
