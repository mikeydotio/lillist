import SwiftUI

/// Plan 21: full-screen choice the user makes when enabling iCloud
/// Sync from LocalOnly. Two destructive options, one safety hatch
/// (export-then-import).
///
/// Pure presentation: the host wires `onReplaceICloud`,
/// `onReplaceLocal`, and `onCancel` to the container.
public struct SyncMigrationChoiceSheet: View {
    public let onReplaceICloud: () -> Void
    public let onReplaceLocal: () -> Void
    public let onCancel: () -> Void

    public init(
        onReplaceICloud: @escaping () -> Void,
        onReplaceLocal: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onReplaceICloud = onReplaceICloud
        self.onReplaceLocal = onReplaceLocal
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.l) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Turn on iCloud Sync")
                    .font(LillistTypography.largeTitle)
                    .foregroundStyle(LillistColor.textStrong)
                    .accessibilityAddTraits(.isHeader)
                Text("Lillist can't merge automatically. Choose which copy to keep.")
                    .font(LillistTypography.body)
                    .foregroundStyle(LillistColor.textMuted)
            }

            VStack(spacing: 12) {
                destructiveOption(
                    action: onReplaceICloud,
                    title: "Replace iCloud with This Device",
                    detail: "Erase everything in iCloud and upload what's on this device. Other devices syncing this iCloud account will see this change."
                )
                destructiveOption(
                    action: onReplaceLocal,
                    title: "Replace This Device with iCloud",
                    detail: "Erase the data on this device and download what's in iCloud. Other devices stay in sync."
                )
            }

            Text("Need both? Export your data first, then import after switching.")
                .font(LillistTypography.caption)
                .foregroundStyle(LillistColor.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
                .buttonStyle(.rainbow(.secondary))
        }
        .padding(LillistSpacing.l)
        .background(LillistColor.workspace)
    }

    /// A destructive choice rendered as a Rainbow card with the urgent
    /// (action-orange) accent stripe and ink heading — the option's
    /// gravity reads from color, not a red wash.
    @ViewBuilder
    private func destructiveOption(
        action: @escaping () -> Void,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        Button(role: .destructive, action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(LillistTypography.headline)
                    .foregroundStyle(RainbowPalette.actionOrange.ink)
                Text(detail)
                    .font(LillistTypography.subheadline)
                    .foregroundStyle(LillistColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .rainbowCard(accent: RainbowPalette.actionOrange.base, elevation: .sm)
        }
        .buttonStyle(.plain)
    }
}
