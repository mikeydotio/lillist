import Foundation

import LillistCore

/// One wedge of the `systemSmall` status donut, as a fraction of the full
/// circle (`0...1`). `start`/`end` are already accumulated — a segment's own
/// slice is `end - start` — so a view can draw it with
/// `Circle().trim(from: start, to: end)` directly.
public struct WidgetDonutSegment: Sendable, Equatable, Identifiable {
    /// What this wedge represents. `.status` when the snapshot carries a real
    /// per-status breakdown; `.unspecifiedOpen` only for a legacy snapshot
    /// (`WidgetSnapshot.statusCounts == nil`) that knows a task is open but not
    /// which of the three open statuses it's in.
    public enum Kind: Sendable, Equatable, Hashable {
        case status(Status)
        case unspecifiedOpen
    }

    public var kind: Kind
    public var count: Int
    public var start: Double
    public var end: Double

    public var id: Kind { kind }

    public init(kind: Kind, count: Int, start: Double, end: Double) {
        self.kind = kind
        self.count = count
        self.start = start
        self.end = end
    }
}

/// The donut's fully-computed content: contiguous segments plus the two
/// scalars the center label and legend need.
public struct WidgetDonutPlan: Sendable, Equatable {
    public var segments: [WidgetDonutSegment]
    /// Remaining (not-yet-closed) task count, for the ring's center label.
    /// Sourced from `statusCounts.open` when available, `snapshot.openCount`
    /// for a legacy snapshot — never the two mixed.
    public var openCount: Int
    /// Whether the glyph legend should render. `false` for a legacy snapshot:
    /// with only `.unspecifiedOpen` + `.closed` to show, a legend would claim
    /// precision (todo vs. started vs. blocked) the payload doesn't have.
    public var showsLegend: Bool

    public init(segments: [WidgetDonutSegment], openCount: Int, showsLegend: Bool) {
        self.segments = segments
        self.openCount = openCount
        self.showsLegend = showsLegend
    }
}

/// Pure arc math for the `systemSmall` status donut (`LIL-96`). No SwiftUI, no
/// WidgetKit — `WidgetStatusDonutView` is the only caller.
public enum WidgetDonutModel {
    /// `Status`'s declaration order (todo → started → blocked → closed) is the
    /// donut's clockwise draw order, starting at 12 o'clock.
    private static let statusOrder: [Status] = [.todo, .started, .blocked, .closed]

    public static func plan(for snapshot: WidgetSnapshot) -> WidgetDonutPlan {
        if let counts = snapshot.statusCounts {
            return plan(countsByStatus: statusOrder.map { ($0, counts[$0]) }, openCount: counts.open)
        }
        // Legacy snapshot: only the open/closed split survives. Never invent a
        // per-status breakdown the payload doesn't actually have.
        let closed = max(0, snapshot.totalCount - snapshot.openCount)
        var segments: [WidgetDonutSegment] = []
        let total = snapshot.openCount + closed
        var offset = 0
        if snapshot.openCount > 0 {
            let end = fraction(offset + snapshot.openCount, of: total)
            segments.append(.init(kind: .unspecifiedOpen, count: snapshot.openCount, start: 0, end: end))
            offset += snapshot.openCount
        }
        if closed > 0 {
            let start = fraction(offset, of: total)
            segments.append(.init(kind: .status(.closed), count: closed, start: start, end: total > 0 ? 1 : 0))
        }
        return WidgetDonutPlan(segments: segments, openCount: snapshot.openCount, showsLegend: false)
    }

    /// Shared segment-building pass for the `statusCounts` path: accumulates
    /// non-zero counts, in the given order, into contiguous `[0...1]` wedges.
    private static func plan(countsByStatus: [(Status, Int)], openCount: Int) -> WidgetDonutPlan {
        let total = countsByStatus.reduce(0) { $0 + $1.1 }
        var segments: [WidgetDonutSegment] = []
        var offset = 0
        for (status, count) in countsByStatus where count > 0 {
            let start = fraction(offset, of: total)
            offset += count
            let end = fraction(offset, of: total)
            segments.append(.init(kind: .status(status), count: count, start: start, end: end))
        }
        return WidgetDonutPlan(segments: segments, openCount: openCount, showsLegend: true)
    }

    /// `numerator / denominator` as a `Double`, snapped to exactly `1.0` at the
    /// end and guarded against a zero denominator (the `totalCount == 0` /
    /// empty-snapshot case, which never reaches this — the caller only builds
    /// segments for a non-zero count — but a defensive guard costs nothing).
    private static func fraction(_ numerator: Int, of denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        if numerator == denominator { return 1 }
        return Double(numerator) / Double(denominator)
    }
}
