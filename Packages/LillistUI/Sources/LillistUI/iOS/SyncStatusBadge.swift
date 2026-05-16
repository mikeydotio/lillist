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
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(
                Group {
                    if case .inProgress = indicator {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }
            )
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch indicator {
        case .idle: return .green
        case .inProgress: return .blue
        case .error: return .red
        }
    }

    private var label: String {
        switch indicator {
        case .idle(let lastSync):
            if let lastSync {
                return "Last synced \(Self.relativeFormatter.localizedString(for: lastSync, relativeTo: Date()))"
            } else {
                return "Sync idle"
            }
        case .inProgress: return "Syncing"
        case .error(let message, _): return "Sync error: \(message)"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
#endif
