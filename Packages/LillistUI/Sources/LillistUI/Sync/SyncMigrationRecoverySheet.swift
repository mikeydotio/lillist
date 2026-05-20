import SwiftUI
import LillistCore

/// Shown on app launch when the `MigrationJournal` is non-idle —
/// indicates the previous run crashed mid-migration. Two paths:
/// restore from the backup we wrote during `.quarantining`, or
/// retry the operation from scratch.
public struct SyncMigrationRecoverySheet: View {
    public let journal: MigrationJournal
    public let onRestoreFromBackup: () -> Void
    public let onTryAgain: () -> Void

    public init(
        journal: MigrationJournal,
        onRestoreFromBackup: @escaping () -> Void,
        onTryAgain: @escaping () -> Void
    ) {
        self.journal = journal
        self.onRestoreFromBackup = onRestoreFromBackup
        self.onTryAgain = onTryAgain
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text("Sync change interrupted")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            VStack(spacing: 12) {
                Button(action: onRestoreFromBackup) {
                    Text("Restore from Backup")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button(action: onTryAgain) {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: 280)
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detail: String {
        let operation = journal.operation.map(operationDescription) ?? "the previous sync change"
        return String(localized: "Lillist couldn't finish \(operation). Restore from the backup we made before the change, or try again.", bundle: .module)
    }

    private func operationDescription(_ op: ModeTransitionOp) -> String {
        switch op {
        case .replaceICloudWithLocal: return "replacing iCloud with this device's data"
        case .replaceLocalWithICloud: return "replacing this device's data with iCloud"
        case .syncFirstThenDisable: return "turning off iCloud Sync (after a final sync)"
        case .disableNow: return "turning off iCloud Sync"
        }
    }
}
