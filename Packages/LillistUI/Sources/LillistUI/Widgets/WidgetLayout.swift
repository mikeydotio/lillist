import Foundation

/// The size class a widget card renders for. Deliberately **not** WidgetKit's
/// `WidgetFamily` — these presentation views live in LillistUI (which never
/// imports WidgetKit), and the widget extension maps `WidgetFamily → WidgetLayout`
/// in its entry view. Only the system (home-screen / desktop) families map here;
/// Lock Screen accessories use the dedicated accessory views instead.
public enum WidgetLayout: Sendable, CaseIterable {
    case small
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
        case .small: 3
        case .medium: 4
        case .large: 9
        case .extraLarge: 15
        }
    }

    /// Whether the "+" quick-add affordance is shown (the small family is too
    /// cramped for it).
    public var showsQuickAdd: Bool {
        self != .small
    }

    /// Whether a non-matching parent may render as a dimmed context row so a
    /// matched subtask can nest under it. `false` only for `.small`: at ~94pt
    /// of title width and only 3 rows, a row spent on a task that isn't even
    /// a match is too costly — an orphaned subtask flattens to the root level
    /// there instead (with the "parent not shown" marker), same as it always
    /// has, rather than displacing a real match.
    public var allowsContextRows: Bool {
        self != .small
    }

    /// Leading indent per nesting tier. `LillistSpacing.m` (12pt), not the
    /// app's own `LillistDragTokens.indentPerLevel` (22pt) — the widget's
    /// tightest title budget (`.small`, ~94pt) can't absorb the app's coarser
    /// indent without truncating titles that would otherwise fit.
    public var indentPerLevel: CGFloat { LillistSpacing.m }

    /// Interior padding inside the dark card.
    public var contentPadding: CGFloat {
        switch self {
        case .small: LillistSpacing.m
        case .medium, .large, .extraLarge: LillistSpacing.l
        }
    }

    /// Vertical spacing between the header and the row stack / between rows.
    public var rowSpacing: CGFloat {
        switch self {
        case .small: LillistSpacing.xs
        case .medium: LillistSpacing.xs
        case .large, .extraLarge: LillistSpacing.s
        }
    }
}
