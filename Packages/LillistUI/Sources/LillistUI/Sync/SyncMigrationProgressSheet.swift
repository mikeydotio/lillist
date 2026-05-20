import SwiftUI
import LillistCore

/// Full-screen progress sheet covering the destructive part of a
/// sync-mode change. Driven by `MigrationPhase` events from
/// `MigrationCoordinator.progressStream`.
///
/// The host owns the sheet's presentation (`.fullScreenCover` on
/// iOS, `.sheet` pinned to keyWindow on macOS); this view just
/// renders the active phase.
public struct SyncMigrationProgressSheet: View {
    public let phase: MigrationPhase
    public let onDismissAfterCompletion: (() -> Void)?

    public init(phase: MigrationPhase, onDismissAfterCompletion: (() -> Void)? = nil) {
        self.phase = phase
        self.onDismissAfterCompletion = onDismissAfterCompletion
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Spacer()

            switch phase {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            default:
                ProgressView()
                    .controlSize(.large)
            }

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if let progress = visibleProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
            }

            Spacer()

            if case .completed = phase, let dismiss = onDismissAfterCompletion {
                Button("Done", action: dismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, LillistSpacing.l)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch phase {
        case .preparing: return String(localized: "Preparing…", bundle: .module)
        case .backingUp: return String(localized: "Backing up your data…", bundle: .module)
        case .markingJournal: return String(localized: "Saving migration state…", bundle: .module)
        case .erasingICloud: return String(localized: "Erasing iCloud data…", bundle: .module)
        case .removingLocalStore: return String(localized: "Removing local data…", bundle: .module)
        case .reconfiguringStore: return String(localized: "Reconfiguring sync…", bundle: .module)
        case .uploading: return String(localized: "Uploading to iCloud…", bundle: .module)
        case .downloading: return String(localized: "Downloading from iCloud…", bundle: .module)
        case .finalizing: return String(localized: "Finalizing…", bundle: .module)
        case .completed: return String(localized: "Sync settings updated", bundle: .module)
        case .failed: return String(localized: "Migration failed", bundle: .module)
        }
    }

    private var detail: String {
        switch phase {
        case .completed: return String(localized: "Your data is ready to go.", bundle: .module)
        case .failed(let reason): return reason
        default: return String(localized: "Don't quit Lillist while this runs.", bundle: .module)
        }
    }

    private var visibleProgress: Double? {
        switch phase {
        case .erasingICloud(let progress): return progress
        case .uploading(let progress): return progress
        case .downloading(let progress): return progress
        default: return nil
        }
    }
}
