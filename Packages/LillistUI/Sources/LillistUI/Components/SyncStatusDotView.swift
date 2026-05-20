import SwiftUI
import LillistCore

public struct SyncStatusDotView: View {
    public var indicator: SyncIndicator
    public var onRetry: () -> Void
    public var onPausedTap: () -> Void
    @State private var showPopover = false
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate
    @Environment(\.differentiateWithoutColorOverride) private var overrideDifferentiate

    public init(
        indicator: SyncIndicator,
        onRetry: @escaping () -> Void,
        onPausedTap: @escaping () -> Void = {}
    ) {
        self.indicator = indicator
        self.onRetry = onRetry
        self.onPausedTap = onPausedTap
    }

    public var body: some View {
        let differentiate = overrideDifferentiate ?? systemDifferentiate
        Button {
            if case .paused = indicator {
                onPausedTap()
            } else {
                showPopover.toggle()
            }
        } label: {
            ZStack {
                if case .paused = indicator {
                    Image(systemName: indicator.systemImage)
                        .font(.system(size: LillistSpacing.s, weight: .regular))
                        .foregroundStyle(indicator.color)
                } else {
                    Circle()
                        .fill(indicator.color)
                        .frame(width: LillistSpacing.s, height: LillistSpacing.s)
                    if differentiate {
                        Image(systemName: indicator.differentiatedSystemImage)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
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
        case .paused(let reason):
            return String(localized: "Sync paused: \(reasonDescription(reason))", bundle: .module)
        }
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

    @ViewBuilder private var detail: some View {
        if case .error(_, let last) = indicator, let last {
            Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
