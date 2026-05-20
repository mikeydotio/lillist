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
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                Button(role: .destructive, action: onConfirm) {
                    Text("Replace")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 420)
    }
}
