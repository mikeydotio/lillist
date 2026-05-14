import SwiftUI

public struct SyncStatusDotView: View {
    public var indicator: SyncIndicator
    public var onRetry: () -> Void
    @State private var showPopover = false

    public init(indicator: SyncIndicator, onRetry: @escaping () -> Void) {
        self.indicator = indicator
        self.onRetry = onRetry
    }

    public var body: some View {
        Button { showPopover.toggle() } label: {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
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
            .padding(12)
            .frame(width: 240)
        }
    }

    private var color: Color {
        switch indicator {
        case .idle(let last):
            guard let last else { return .yellow }
            return Date().timeIntervalSince(last) < 60 ? .green : .yellow
        case .inProgress:
            return .blue
        case .error:
            return .red
        }
    }

    private var label: String {
        switch indicator {
        case .idle(let last):
            return last.map { "Last synced \(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()))" } ?? "Not synced yet"
        case .inProgress: return "Syncing…"
        case .error(let msg, _): return "Sync error: \(msg)"
        }
    }

    @ViewBuilder private var detail: some View {
        if case .error(_, let last) = indicator, let last {
            Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
