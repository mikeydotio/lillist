import SwiftUI

import LillistCore

/// `LIL-96`: the `.systemSmall` widget surface — a status-composition donut
/// replacing the task-title list that size could never render well (3 rows,
/// ~94pt of title width). Renders the filter's todo/started/blocked/closed
/// breakdown as a ring, the remaining count at its center, and a compact
/// glyph legend below — the shape axis (`StatusGlyph`) that keeps the
/// breakdown legible without relying on color alone.
///
/// Unlike `WidgetFilterCardView`, this view takes no `WidgetLayout` — it is
/// the one, fixed presentation for exactly one family. Tap-only: the
/// whole-widget `.widgetURL` (wired in the extension) is the only
/// interaction, same as `.small` has always had (it never got the "+").
public struct WidgetStatusDonutView: View {
    public var snapshot: WidgetSnapshot

    @ScaledMetric(relativeTo: .body) private var strokeWidth: CGFloat = 12

    public init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    private var plan: WidgetDonutPlan {
        WidgetDonutModel.plan(for: snapshot)
    }

    public var body: some View {
        VStack(spacing: LillistSpacing.xs) {
            if !snapshot.isUnfiltered {
                titleRow
            }
            if snapshot.totalCount == 0 {
                WidgetAllClearView()
            } else {
                ring
                if plan.showsLegend {
                    legend
                }
            }
        }
        .padding(LillistSpacing.m)
        .widgetCardChrome()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var titleRow: some View {
        Text(snapshot.filterName)
            .font(LillistTypography.subheadline)
            .fontWeight(.bold)
            .foregroundStyle(LillistColor.textStrong)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Segments draw clockwise from 12 o'clock: each trimmed `Circle` is
    /// rotated individually (not the whole `ZStack`), so `centerContent`
    /// stays upright. No `Canvas`/`.drawingGroup()` — both blank the entire
    /// offscreen capture in the macOS snapshot harness; plain
    /// `Circle().trim().stroke()` renders fine offscreen.
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(LillistColor.borderSoft, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
            ForEach(plan.segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(color(for: segment.kind), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            centerContent
        }
        .padding(strokeWidth / 2)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Zero-count statuses are never given a minimum arc — distorting the
    /// proportions to make a sliver visible would misrepresent the filter's
    /// actual composition; the legend is the precise channel for small counts.
    @ViewBuilder
    private var centerContent: some View {
        if plan.openCount == 0 {
            VStack(spacing: 2) {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(StatusPalette.color(for: .closed))
                Text("All done", bundle: .module)
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textMuted)
            }
        } else {
            VStack(spacing: 0) {
                Text("\(plan.openCount)")
                    .font(LillistTypography.title)
                    .monospacedDigit()
                    .foregroundStyle(LillistColor.textStrong)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("left", bundle: .module)
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textMuted)
            }
            .padding(.horizontal, LillistSpacing.xs)
        }
    }

    /// Only reachable when `plan.showsLegend` — i.e. `statusCounts` was
    /// present, so every segment is `.status`, never `.unspecifiedOpen`.
    private var legend: some View {
        HStack(spacing: LillistSpacing.s) {
            ForEach(plan.segments) { segment in
                if case let .status(status) = segment.kind {
                    HStack(spacing: 3) {
                        Image(systemName: StatusGlyph.symbol(for: status))
                            .font(.system(size: 9))
                            .foregroundStyle(StatusPalette.color(for: status))
                        Text("\(segment.count)")
                            .font(LillistTypography.caption2)
                            .foregroundStyle(LillistColor.textMuted)
                            .monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func color(for kind: WidgetDonutSegment.Kind) -> Color {
        switch kind {
        case .status(let status): StatusPalette.color(for: status)
        case .unspecifiedOpen: LillistColor.textFaint
        }
    }

    // MARK: - Accessibility

    /// Built from already-localized parts joined by plain interpolation —
    /// the same idiom `WidgetContextRowView.accessibilityLabel` (LIL-95)
    /// uses, rather than one composite key per status combination.
    private var accessibilityLabel: String {
        var parts: [String] = []
        if !snapshot.isUnfiltered {
            parts.append(snapshot.filterName)
        }
        if snapshot.totalCount == 0 {
            parts.append(String(localized: "All clear", bundle: .module))
        } else if plan.openCount == 0 {
            parts.append(String(localized: "All done", bundle: .module))
        } else {
            for segment in plan.segments {
                switch segment.kind {
                case .status(let status):
                    parts.append("\(segment.count) \(StatusGlyph.accessibilityLabel(for: status))")
                case .unspecifiedOpen:
                    parts.append(String(localized: "\(segment.count) left", bundle: .module))
                }
            }
        }
        return parts.joined(separator: ", ")
    }
}
