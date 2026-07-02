import SwiftUI

import LillistCore

/// A small progress ring showing the done fraction of a filter's tasks. Empty
/// (0% done) renders as a plain muted ring.
private struct WidgetProgressRing: View {
    var open: Int
    var total: Int
    var tint: Color

    var body: some View {
        let fraction = total > 0 ? Double(total - open) / Double(total) : 0
        ZStack {
            Circle().stroke(LillistColor.borderStrong, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
    }
}

/// The widget header: a done-progress ring, the filter name (bold), and an
/// optional trailing remaining-count.
public struct WidgetHeaderView: View {
    public var snapshot: WidgetSnapshot
    public var showsCount: Bool

    public init(snapshot: WidgetSnapshot, showsCount: Bool = true) {
        self.snapshot = snapshot
        self.showsCount = showsCount
    }

    private var tint: Color {
        Color(hex: snapshot.tintHex) ?? RainbowPalette.Spectrum.purple
    }

    public var body: some View {
        HStack(spacing: LillistSpacing.s) {
            WidgetProgressRing(open: snapshot.openCount, total: snapshot.totalCount, tint: tint)
            Text(snapshot.filterName)
                .font(LillistTypography.headline)
                .fontWeight(.bold)
                .foregroundStyle(LillistColor.textStrong)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if showsCount {
                Text("\(snapshot.openCount)")
                    .font(LillistTypography.subheadline)
                    .foregroundStyle(LillistColor.textMuted)
                    .monospacedDigit()
            }
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
            WidgetHeaderView(snapshot: snapshot, showsCount: layout.showsHeaderCount)
            if snapshot.tasks.isEmpty {
                emptyState
            } else {
                ForEach(visibleRows) { row in
                    WidgetTaskRowView(row: row, titleURL: rowURL(row)) { rowLeading(row) }
                }
            }
            Spacer(minLength: 0)
            if layout.showsQuickAdd {
                HStack {
                    Spacer(minLength: 0)
                    quickAdd
                }
            }
        }
        .padding(layout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: LillistRadius.l, style: .continuous)
                .fill(LillistColor.card)
        )
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: LillistRadius.xl, style: .continuous)
                .fill(Self.frameGradient)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

extension WidgetFilterCardView where RowLeading == WidgetCheckGlyph {
    /// Non-interactive convenience: renders plain status glyphs (previews,
    /// snapshot tests).
    public init(snapshot: WidgetSnapshot, layout: WidgetLayout, addURL: URL? = nil) {
        self.init(snapshot: snapshot, layout: layout, addURL: addURL) {
            WidgetCheckGlyph(status: $0.status)
        }
    }
}
