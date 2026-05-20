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
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Lillist can't merge automatically. Choose which copy to keep.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Button(role: .destructive, action: onReplaceICloud) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replace iCloud with This Device")
                            .font(.headline)
                        Text("Erase everything in iCloud and upload what's on this device. Other devices syncing this iCloud account will see this change.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button(role: .destructive, action: onReplaceLocal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Replace This Device with iCloud")
                            .font(.headline)
                        Text("Erase the data on this device and download what's in iCloud. Other devices stay in sync.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            Text("Need both? Export your data first, then import after switching.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button("Cancel", action: onCancel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .padding(LillistSpacing.l)
    }
}
