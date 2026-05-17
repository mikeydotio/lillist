import SwiftUI

public struct SyncStatusDotView: View {
    public var indicator: SyncIndicator
    public var onRetry: () -> Void
    @State private var showPopover = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var overrideDifferentiate

    public init(indicator: SyncIndicator, onRetry: @escaping () -> Void) {
        self.indicator = indicator
        self.onRetry = onRetry
    }

    public var body: some View {
        let differentiate = overrideDifferentiate ?? systemDifferentiate
        Button { showPopover.toggle() } label: {
            ZStack {
                Circle()
                    .fill(indicator.color)
                    .frame(width: LillistSpacing.s, height: LillistSpacing.s)
                if differentiate {
                    Image(systemName: indicator.differentiatedSystemImage)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityLabel(label)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).font(.headline)
                detail
                if case .error = indicator {
                    Button("Try again", action: onRetry)
                }
            }
            .padding(LillistSpacing.m)
            .frame(width: 240)
        }
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
            }
        }
    }

    private var label: String {
        switch indicator {
        case .idle(let last):
            if let last {
                let relative = Self.relativeFormatter.localizedString(for: last, relativeTo: Date())
                return String(localized: "Last synced \(relative)", bundle: .module)
            } else {
                return String(localized: "Not synced yet", bundle: .module)
            }
        case .inProgress:
            return String(localized: "Syncing…", bundle: .module)
        case .error(let msg, _):
            return String(localized: "Sync error: \(msg)", bundle: .module)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    @ViewBuilder private var detail: some View {
        if case .error(_, let last) = indicator, let last {
            Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
