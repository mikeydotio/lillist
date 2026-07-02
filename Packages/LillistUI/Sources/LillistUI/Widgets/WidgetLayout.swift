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

    /// Maximum task rows to render for this size.
    public var maxRows: Int {
        switch self {
        case .small: 3
        case .medium: 3
        case .large: 8
        case .extraLarge: 14
        }
    }

    /// Whether the "+" quick-add affordance is shown (the small family is too
    /// cramped for it).
    public var showsQuickAdd: Bool {
        self != .small
    }

    /// Whether the header shows the trailing remaining-count.
    public var showsHeaderCount: Bool {
        self != .small
    }

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
