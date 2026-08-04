import SwiftUI

import LillistCore

/// The widget header, pinned to the top-trailing corner: the filter name (bold,
/// only when a saved filter is applied) followed by the remaining-task count.
/// The unfiltered "No Filter" view shows the count alone.
public struct WidgetHeaderView: View {
    public var snapshot: WidgetSnapshot

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            Spacer(minLength: 0)
            if !snapshot.isUnfiltered {
                Text(snapshot.filterName)
                    .font(LillistTypography.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(LillistColor.textStrong)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text("\(snapshot.openCount)")
                .font(LillistTypography.subheadline)
                .foregroundStyle(LillistColor.textMuted)
                .monospacedDigit()
        }
    }
}

/// The "+" quick-add affordance shown bottom-right. Pure visual; the widget
/// extension wraps it in a `Link` to the Quick Capture deep link.
public struct WidgetQuickAddButton: View {
    public init() {}

    public var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(LillistColor.textMuted)
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(LillistColor.borderStrong, lineWidth: 1.5))
            .accessibilityLabel(Text("Add task", bundle: .module))
    }
}

/// `LIL-95`: a non-matching parent, rendered only so its matching
/// descendants have somewhere to nest. Deliberately **not**
/// `WidgetTaskRowView` — it never receives a `rowLeading`/`rowURL` closure, so
/// it structurally cannot become a `Button(intent:)` or a `Link`: tapping a
/// task that didn't match the filter would be surprising, so the tap falls
/// through to the whole-widget `.widgetURL` (opens the filter) instead.
private struct WidgetContextRowView: View {
    let row: WidgetSnapshot.Row
    let depth: Int
    let indentPerLevel: CGFloat

    var body: some View {
        HStack(spacing: LillistSpacing.m) {
            if depth > 0 {
                // See `WidgetTaskRowView`'s identical gutter: `height: 0`
                // stops this `Color.clear` from greedily filling the row's
                // vertical space in this plain-`VStack` card.
                Color.clear.frame(width: CGFloat(depth) * indentPerLevel, height: 0)
            }
            WidgetStatusChip(status: row.status)
            Text(row.title)
                .font(LillistTypography.body)
                .foregroundStyle(LillistColor.textStrong)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        // The app's one canonical "recede" opacity (`RainbowCard`'s done-row
        // fade) — reused here so a context row reads as present-but-inert by
        // the same visual language the app already uses for de-emphasis.
        .opacity(0.62)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let status = StatusGlyph.accessibilityLabel(for: row.status)
        let suffix = String(localized: "not part of this filter", bundle: .module)
        return "\(row.title), \(status), \(suffix)"
    }
}

/// The signature widget surface: a rainbow-bordered dark card holding a filter's
/// header + task rows + quick-add button. Drives the `systemSmall/Medium/Large/
/// ExtraLarge` families (Lock Screen accessories use separate views).
///
/// `RowLeading` is injected so the widget extension can supply an interactive
/// `Button(intent:)`-wrapped status glyph; the convenience initializer renders
/// plain glyphs for previews and snapshot tests. `addURL`, when set, wraps the
/// quick-add button in a `Link`.
///
/// No Liquid Glass (it doesn't render in widgets): solid `LillistColor` fills +
/// a `RainbowGradient`-style angular border, which do render.
public struct WidgetFilterCardView<RowLeading: View>: View {
    private let snapshot: WidgetSnapshot
    private let layout: WidgetLayout
    private let addURL: URL?
    private let rowURL: (WidgetSnapshot.Row) -> URL?
    private let rowLeading: (WidgetSnapshot.Row) -> RowLeading

    public init(
        snapshot: WidgetSnapshot,
        layout: WidgetLayout,
        addURL: URL? = nil,
        rowURL: @escaping (WidgetSnapshot.Row) -> URL? = { _ in nil },
        @ViewBuilder rowLeading: @escaping (WidgetSnapshot.Row) -> RowLeading
    ) {
        self.snapshot = snapshot
        self.layout = layout
        self.addURL = addURL
        self.rowURL = rowURL
        self.rowLeading = rowLeading
    }

    /// `LIL-95`: re-caps the (already tree-shaped) snapshot at this family's
    /// `maxRows` via the same shared planner ``WidgetSnapshotBuilder`` used to
    /// cap the persisted snapshot at `rowCap` — one implementation of the
    /// stranded-context-row and re-leveling rules for both cap points.
    private var visibleItems: [WidgetRowPlan.Item] {
        WidgetRowPlan.plan(rows: snapshot.tasks, limit: layout.maxRows, allowsContextRows: layout.allowsContextRows)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: layout.rowSpacing) {
            WidgetHeaderView(snapshot: snapshot)
            if snapshot.tasks.isEmpty {
                WidgetAllClearView()
            } else {
                ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                    rowView(for: item)
                        // Only the bottom row shares the "+"'s horizontal band, so
                        // inset just its trailing edge to keep the title clear of
                        // the overlaid glyph; every row above spans full width.
                        .padding(.trailing, trailingInset(isLast: index == visibleItems.count - 1))
                }
            }
            // Top-anchor the rows when there are fewer than fill height; the
            // "+" is an overlay (below), so it no longer consumes a row band.
            Spacer(minLength: 0)
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if layout.showsQuickAdd {
                quickAdd.padding(layout.contentPadding)
            }
        }
        .widgetCardChrome()
    }

    /// Trailing inset for the bottom-most visible row so its tail-truncated
    /// title clears the bottom-trailing "+" overlay (30pt glyph + a gap). Rows
    /// above the last one, and every row when the "+" is hidden, get no inset.
    private func trailingInset(isLast: Bool) -> CGFloat {
        guard isLast, layout.showsQuickAdd else { return 0 }
        return 30 + LillistSpacing.m
    }

    /// A context row renders itself — dimmed, no `rowLeading`/`rowURL` call —
    /// so `AdvanceTaskStatusFromWidget` can never be handed a row it didn't
    /// match. Every other row is unchanged from before `LIL-95`: at `depth: 0`
    /// with no marker, `WidgetTaskRowView` renders byte-identically to the
    /// pre-nesting layout.
    @ViewBuilder
    private func rowView(for item: WidgetRowPlan.Item) -> some View {
        if item.row.isContext {
            WidgetContextRowView(row: item.row, depth: item.depth, indentPerLevel: layout.indentPerLevel)
        } else {
            WidgetTaskRowView(
                row: item.row,
                titleURL: rowURL(item.row),
                depth: item.depth,
                showsParentMarker: item.showsParentMarker,
                indentPerLevel: layout.indentPerLevel
            ) { rowLeading(item.row) }
        }
    }

    @ViewBuilder
    private var quickAdd: some View {
        if let addURL {
            Link(destination: addURL) { WidgetQuickAddButton() }
        } else {
            WidgetQuickAddButton()
        }
    }

}

extension WidgetFilterCardView where RowLeading == WidgetStatusChip {
    /// Non-interactive convenience: renders the app's status chip (previews,
    /// snapshot tests). The widget extension supplies an interactive
    /// `Button(intent:)`-wrapped `WidgetStatusChip` for tap-to-cycle.
    public init(snapshot: WidgetSnapshot, layout: WidgetLayout, addURL: URL? = nil) {
        self.init(snapshot: snapshot, layout: layout, addURL: addURL) {
            WidgetStatusChip(status: $0.status)
        }
    }
}
