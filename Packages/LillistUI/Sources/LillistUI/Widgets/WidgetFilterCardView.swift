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

    /// Full-spectrum angular gradient for the border frame. The trailing purple
    /// closes the loop seamlessly (orange → purple).
    private static var frameGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: RainbowPalette.Spectrum.stops + [RainbowPalette.Spectrum.purple]),
            center: .center
        )
    }

    private var visibleRows: [WidgetSnapshot.Row] {
        Array(snapshot.tasks.prefix(layout.maxRows))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: layout.rowSpacing) {
            WidgetHeaderView(snapshot: snapshot)
            if snapshot.tasks.isEmpty {
                emptyState
            } else {
                ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                    WidgetTaskRowView(row: row, titleURL: rowURL(row)) { rowLeading(row) }
                        // Only the bottom row shares the "+"'s horizontal band, so
                        // inset just its trailing edge to keep the title clear of
                        // the overlaid glyph; every row above spans full width.
                        .padding(.trailing, trailingInset(isLast: index == visibleRows.count - 1))
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
        // `ContainerRelativeShape` renders concentric with the widget's own
        // corner radius (which grew on iOS 26/27), so the card fill and the
        // rainbow border both hug the widget edge instead of the old fixed 16/22pt
        // radius that left a visible corner gap. The inner fill, inset by
        // `.padding(4)`, stays concentric automatically.
        .background(ContainerRelativeShape().fill(LillistColor.card))
        .padding(4)
        .background(ContainerRelativeShape().fill(Self.frameGradient))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Trailing inset for the bottom-most visible row so its tail-truncated
    /// title clears the bottom-trailing "+" overlay (30pt glyph + a gap). Rows
    /// above the last one, and every row when the "+" is hidden, get no inset.
    private func trailingInset(isLast: Bool) -> CGFloat {
        guard isLast, layout.showsQuickAdd else { return 0 }
        return 30 + LillistSpacing.m
    }

    @ViewBuilder
    private var quickAdd: some View {
        if let addURL {
            Link(destination: addURL) { WidgetQuickAddButton() }
        } else {
            WidgetQuickAddButton()
        }
    }

    private var emptyState: some View {
        VStack(spacing: LillistSpacing.s) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26))
                .foregroundStyle(StatusPalette.color(for: .closed))
            Text("All clear", bundle: .module)
                .font(LillistTypography.subheadline)
                .foregroundStyle(LillistColor.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, LillistSpacing.l)
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
