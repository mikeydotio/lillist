import SwiftUI
import LillistCore

/// Full-screen progress sheet covering the destructive part of a
/// sync-mode change. Driven by `MigrationPhase` events from
/// `MigrationCoordinator.progressStream`.
///
/// The host owns the sheet's presentation (`.fullScreenCover` on
/// iOS, `.sheet` pinned to keyWindow on macOS) **and** its dismissal:
/// on success the host closes the sheet silently (no "all done" screen);
/// only `.failed` is rendered for the user to read and dismiss. This view
/// just renders the active phase.
public struct SyncMigrationProgressSheet: View {
    public let phase: MigrationPhase

    public init(phase: MigrationPhase) {
        self.phase = phase
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.l) {
            Spacer()

            switch phase {
            case .completed:
                // Completion is a sanctioned rainbow moment.
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(RainbowGradient.vertical)
                    .accessibilityHidden(true)
            case .failed:
                Image(systemName: "xmark.octagon.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(RainbowPalette.actionOrange.deep)
                    .accessibilityHidden(true)
            default:
                ProgressView()
                    .controlSize(.large)
            }

            Text(title)
                .font(LillistTypography.title2)
                .foregroundStyle(LillistColor.textStrong)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(detail)
                .font(LillistTypography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(LillistColor.textMuted)
                .frame(maxWidth: 420)

            if let progress = visibleProgress {
                RainbowProgressBar(value: progress)
                    .frame(maxWidth: 320)
            }

            Spacer()
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LillistColor.workspace)
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

/// Inset Rainbow progress meter: sunken track, glossy spectrum fill
/// that reaches the orange end as work completes. Mirrors the
/// system's accessibility behavior by wrapping a hidden ProgressView
/// representation.
struct RainbowProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.rainbowWell)
                Capsule()
                    .fill(RainbowGradient.horizontal)
                    .frame(width: max(8, proxy.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 8)
        .accessibilityRepresentation {
            ProgressView(value: min(max(value, 0), 1))
        }
    }
}
