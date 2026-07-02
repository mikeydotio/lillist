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

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.filterName)
                .font(.headline)
                .lineLimit(1)
            if snapshot.tasks.isEmpty {
                Text("All clear", bundle: .module)
                    .font(.caption)
            } else {
                ForEach(snapshot.tasks.prefix(2)) { row in
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
