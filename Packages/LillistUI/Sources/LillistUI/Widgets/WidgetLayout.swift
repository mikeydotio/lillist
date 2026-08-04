import Foundation

/// The size class a widget card renders for. Deliberately **not** WidgetKit's
/// `WidgetFamily` — these presentation views live in LillistUI (which never
/// imports WidgetKit), and the widget extension maps `WidgetFamily → WidgetLayout`
/// in its entry view. Only the system (home-screen / desktop) card families map
/// here; `.systemSmall` renders `WidgetStatusDonutView` instead (`LIL-96`) and
/// Lock Screen accessories use the dedicated accessory views.
public enum WidgetLayout: Sendable, CaseIterable {
    case medium
    case large
    case extraLarge

    /// Maximum task rows to render for this size. The quick-add "+" is a
    /// bottom-trailing overlay (not a footer that consumes a row band), so the
    /// medium/large/extraLarge caps reclaim that freed row. `extraLarge` stays
    /// `≤ WidgetSnapshotBuilder.defaultRowCap` (24, as of `LIL-95` — dimmed
    /// context rows consume this budget too) so the snapshot can fill it.
    public var maxRows: Int {
        switch self {
        case .medium: 4
        case .large: 9
        case .extraLarge: 15
        }
    }

    /// Leading indent per nesting tier. `LillistSpacing.m` (12pt), not the
    /// app's own `LillistDragTokens.indentPerLevel` (22pt) — the widget's
    /// title budget can't absorb the app's coarser indent without truncating
    /// titles that would otherwise fit.
    public var indentPerLevel: CGFloat { LillistSpacing.m }

    /// Interior padding inside the dark card.
    public var contentPadding: CGFloat { LillistSpacing.l }

    /// Vertical spacing between the header and the row stack / between rows.
    public var rowSpacing: CGFloat {
        switch self {
        case .medium: LillistSpacing.xs
        case .large, .extraLarge: LillistSpacing.s
        }
    }
}
