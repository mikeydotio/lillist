import SwiftUI

/// Plan 21: the second-tap confirmation before a destructive
/// sync-mode change runs. Surfaced as a native confirmation dialog
/// from the host; this view is a thin presentation wrapper carrying
/// the right copy.
public struct SyncMigrationConfirmationDialog: View {
    public enum Direction: Sendable {
        case replaceICloud
        case replaceLocal
    }

    public let direction: Direction
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public init(direction: Direction, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.direction = direction
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var title: String {
        switch direction {
        case .replaceICloud: return String(localized: "Replace iCloud with This Device?", bundle: .module)
        case .replaceLocal: return String(localized: "Replace This Device with iCloud?", bundle: .module)
        }
    }

    public var message: String {
        switch direction {
        case .replaceICloud:
            return String(localized: "This permanently replaces iCloud's data with what's on this device. Other devices syncing this iCloud account will see this change. This cannot be undone.", bundle: .module)
        case .replaceLocal:
            return String(localized: "This permanently replaces this device's data with what's in iCloud. This cannot be undone.", bundle: .module)
        }
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(RainbowPalette.actionOrange.deep)
                .accessibilityHidden(true)
            Text(title)
                .font(LillistTypography.title3)
                .foregroundStyle(LillistColor.textStrong)
                .multilineTextAlignment(.center)
            Text(message)
                .font(LillistTypography.subheadline)
                .foregroundStyle(LillistColor.textMuted)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button(role: .destructive, action: onConfirm) {
                    Text("Replace")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.rainbow(.orange))
                Button("Cancel", action: onCancel)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.rainbow(.secondary))
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 420)
        .background(LillistColor.workspace)
    }
}
