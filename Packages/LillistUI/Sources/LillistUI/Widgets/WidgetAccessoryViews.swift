#if os(iOS)
import SwiftUI

import LillistCore

/// Lock Screen / StandBy accessory widgets. iOS-only (macOS has no accessory
/// families). System fonts + default foreground on purpose: the OS renders
/// accessories in a vibrant, desaturated mode, so custom hues/fonts read poorly.

/// Inline accessory: a single tinted line — "FilterName · N".
public struct WidgetAccessoryInlineView: View {
    public var snapshot: WidgetSnapshot
    public init(snapshot: WidgetSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        Label {
            Text(verbatim: "\(snapshot.filterName) · \(snapshot.openCount)")
        } icon: {
            Image(systemName: "checklist")
        }
    }
}

/// Circular accessory: a capacity ring of the done-fraction with the remaining
/// count in the center.
public struct WidgetAccessoryCircularView: View {
    public var snapshot: WidgetSnapshot
    public init(snapshot: WidgetSnapshot) { self.snapshot = snapshot }

    public var body: some View {
        let done = snapshot.totalCount - snapshot.openCount
        let fraction = snapshot.totalCount > 0 ? Double(done) / Double(snapshot.totalCount) : 0
        Gauge(value: fraction) {
            Image(systemName: "checklist")
        } currentValueLabel: {
            Text(verbatim: "\(snapshot.openCount)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

/// Rectangular accessory: filter name + up to two task titles (or an all-clear
/// line when empty).
public struct WidgetAccessoryRectangularView: View {
    public var snapshot: WidgetSnapshot
    public init(snapshot: WidgetSnapshot) { self.snapshot = snapshot }

    /// `LIL-95`: this accessory renders bare titles with no chip, no indent,
    /// and no marker — nesting isn't meaningful at this size, but a dimmed
    /// **context** row (a non-match shown only for the card families' tree)
    /// would otherwise render here indistinguishable from a real match. Filter
    /// it out rather than teach this view about `WidgetRowPlan`.
    private var matchedTasks: [WidgetSnapshot.Row] {
        snapshot.tasks.filter { !$0.isContext }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.filterName)
                .font(.headline)
                .lineLimit(1)
            if matchedTasks.isEmpty {
                Text("All clear", bundle: .module)
                    .font(.caption)
            } else {
                ForEach(matchedTasks.prefix(2)) { row in
                    Text(row.title)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
