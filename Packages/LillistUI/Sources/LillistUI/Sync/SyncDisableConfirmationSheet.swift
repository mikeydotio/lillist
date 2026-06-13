import SwiftUI

/// Plan 21: confirmation sheet the user sees when toggling iCloud
/// Sync OFF. Two options: sync one more time first, or disconnect
/// immediately.
public struct SyncDisableConfirmationSheet: View {
    public let onSyncFirst: () -> Void
    public let onDisableNow: () -> Void
    public let onCancel: () -> Void

    public init(
        onSyncFirst: @escaping () -> Void,
        onDisableNow: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSyncFirst = onSyncFirst
        self.onDisableNow = onDisableNow
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
                .accessibilityHidden(true)

            Text("Disable iCloud Sync?")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Sync one final time first? Your iCloud data will be preserved.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            VStack(spacing: 12) {
                Button(action: onSyncFirst) {
                    Text("Sync First")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onDisableNow) {
                    Text("Disable Now")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                Button("Cancel", action: onCancel)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 280)
        }
        .padding(LillistSpacing.l)
    }
}
