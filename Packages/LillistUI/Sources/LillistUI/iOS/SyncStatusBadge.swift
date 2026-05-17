#if os(iOS)
import SwiftUI

/// Small badge surfaced in the top-right of each primary iOS view.
/// Mirrors design Section 8's sync-indicator semantics, driven by the
/// shared LillistUI `SyncIndicator` enum (also used by the macOS app).
public struct SyncStatusBadge: View {
    public var indicator: SyncIndicator

    public init(indicator: SyncIndicator) {
        self.indicator = indicator
    }

    public var body: some View {
        Circle()
            .fill(indicator.color)
            .frame(width: LillistSpacing.s + 2, height: LillistSpacing.s + 2)
            .overlay(
                Group {
                    if case .inProgress = indicator {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
            )
            // Plan 13 fallout: keep the outer 44pt hit area + content
            // shape + .isStaticText trait introduced by Plan 13 Task 8.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isStaticText)
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
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
#endif
