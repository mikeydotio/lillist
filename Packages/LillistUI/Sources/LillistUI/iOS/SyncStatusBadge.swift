#if os(iOS)
import SwiftUI
import LillistCore

/// Small badge surfaced in the top-right of each primary iOS view.
/// Mirrors design Section 8's sync-indicator semantics, driven by the
/// shared LillistUI `SyncIndicator` enum (also used by the macOS app).
///
/// Plan 21: the badge is now a `Button`. When the indicator is
/// `.paused(reason:)`, tapping the badge invokes `onPausedTap` so the
/// host can present `PauseExplainerDialog`. For other states the tap
/// is inert (the indicator is still informational; the dot is the
/// reachable hit target). The 44pt hit area survives unchanged.
public struct SyncStatusBadge: View {
    public var indicator: SyncIndicator
    public var onPausedTap: () -> Void
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var overrideDifferentiate

    public init(indicator: SyncIndicator, onPausedTap: @escaping () -> Void = {}) {
        self.indicator = indicator
        self.onPausedTap = onPausedTap
    }

    public var body: some View {
        let differentiate = overrideDifferentiate ?? systemDifferentiate
        Button {
            if case .paused = indicator { onPausedTap() }
        } label: {
            ZStack {
                if case .paused = indicator {
                    Image(systemName: indicator.systemImage)
                        .font(.system(size: LillistSpacing.s + 2, weight: .regular))
                        .foregroundStyle(indicator.color)
                } else {
                    Circle()
                        .fill(indicator.color)
                        .frame(width: LillistSpacing.s + 2, height: LillistSpacing.s + 2)
                        .overlay(
                            Group {
                                if differentiate {
                                    Image(systemName: indicator.differentiatedSystemImage)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                } else if case .inProgress = indicator {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                }
                            }
                        )
                }
            }
            // Plan 13 fallout: keep the outer 44pt hit area + content
            // shape introduced by Plan 13 Task 8.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isStaticText)
        .onChange(of: indicator) { _, new in
            switch new {
            case .inProgress:
                AccessibilityAnnouncements.post(
                    String(localized: "Syncing to iCloud", bundle: .module),
                    priority: .low
                )
            case .idle:
                AccessibilityAnnouncements.post(
                    String(localized: "Sync complete", bundle: .module),
                    priority: .low
                )
            case .error(let msg, _):
                AccessibilityAnnouncements.post(
                    String(localized: "Sync error: \(msg)", bundle: .module),
                    priority: .high
                )
            case .paused(let reason):
                AccessibilityAnnouncements.post(
                    String(localized: "Sync paused: \(reasonDescription(reason))", bundle: .module),
                    priority: .high
                )
            }
        }
    }

    private var label: String {
        switch indicator {
        case .idle(let lastSync):
            if let lastSync {
                let relative = Self.relativeFormatter.localizedString(for: lastSync, relativeTo: Date())
                return String(localized: "Last synced \(relative)", bundle: .module)
            } else {
                return String(localized: "Sync idle", bundle: .module)
            }
        case .inProgress:
            return String(localized: "Syncing", bundle: .module)
        case .error(let message, _):
            return String(localized: "Sync error: \(message)", bundle: .module)
        case .paused(let reason):
            return String(localized: "Sync paused: \(reasonDescription(reason))", bundle: .module)
        }
    }

    private var hint: String {
        if case .paused = indicator {
            return String(localized: "Double tap to learn why.", bundle: .module)
        }
        return ""
    }

    private func reasonDescription(_ reason: PauseReason) -> String {
        switch reason {
        case .noAccount: return String(localized: "iCloud is not signed in.", bundle: .module)
        case .restricted: return String(localized: "iCloud is restricted on this device.", bundle: .module)
        case .accountChanged: return String(localized: "Your iCloud account changed.", bundle: .module)
        case .noNetwork: return String(localized: "No internet connection.", bundle: .module)
        case .iCloudDriveDisabled: return String(localized: "iCloud Drive is turned off for Lillist.", bundle: .module)
        case .unknown: return String(localized: "Sync is paused.", bundle: .module)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
#endif
