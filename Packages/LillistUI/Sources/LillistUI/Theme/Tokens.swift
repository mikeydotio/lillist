import SwiftUI
import Foundation

/// Lillist design tokens, Plan 14.
///
/// All shared visual constants live here. Adding a new spacing /
/// radius / timing value? Put it in the relevant enum and use the
/// token at the callsite rather than a magic number. Typography is
/// **semantic** — `LillistTypography.title2` maps to SwiftUI's
/// `.title2`, which respects Dynamic Type. Never reintroduce
/// `.font(.system(size: N, weight: …))` for app chrome; it freezes
/// the user's accessibility text-size preference.

/// Vertical and horizontal spacing scale. Use these instead of raw
/// CGFloat literals for padding, stack spacing, and frame insets.
public enum LillistSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 40
}

/// Corner-radius scale for cards, popovers, and floating surfaces.
public enum LillistRadius {
    public static let s: CGFloat = 6
    public static let m: CGFloat = 12
    public static let l: CGFloat = 18
}

/// Gesture-timing constants. `longPress` is the duration we expect a
/// user to hold before a long-press-bound action fires. Used by
/// `StatusIndicatorView` and `FloatingAddButton`.
public enum LillistTiming {
    public static let longPress: TimeInterval = 0.4
}

/// Semantic typography. Each case maps to a SwiftUI `Font` that
/// participates in Dynamic Type. Use `LillistTypography.title` not
/// `.font(.system(size: 28, weight: .semibold))` so user accessibility
/// settings actually affect chrome text size.
public enum LillistTypography {
    /// `.largeTitle` — onboarding heroes, splash screens.
    public static let largeTitle: Font = .largeTitle
    /// `.title` — major headings.
    public static let title: Font = .title
    /// `.title2` — sheet headers like the onboarding "Welcome to Lillist".
    public static let title2: Font = .title2
    /// `.title3` — secondary headings, sub-section titles.
    public static let title3: Font = .title3
    /// `.headline` — emphasized body, sidebar group labels.
    public static let headline: Font = .headline
    /// `.body` — default text in most form rows.
    public static let body: Font = .body
    /// `.subheadline` — captions under titles, supporting text.
    public static let subheadline: Font = .subheadline
    /// `.caption` — small descriptive labels (tag chips, badges).
    public static let caption: Font = .caption
    /// `.caption2` — date/time stamps in journal rows.
    public static let caption2: Font = .caption2
    /// Status-indicator glyph. Semantic equivalent of a 16pt SF Symbol
    /// rendered at body weight. Used by `StatusIndicatorView`.
    public static let statusGlyph: Font = .body
    /// Quick-capture field text. Semantic equivalent of a slightly-
    /// larger body weight.
    public static let quickCaptureField: Font = .title3
    /// Floating add button "+" glyph.
    public static let floatingAddGlyph: Font = .title.weight(.semibold)
}

/// Reusable string constants used by app-target preferences UI.
public enum LillistTokens {
    /// Default tint hex applied to new tags when the user hasn't
    /// overridden the preference. Previously duplicated as a string
    /// literal in `GeneralSection.swift` (iOS) and `GeneralPane.swift`
    /// (macOS). Plan 14 collapsed those into this single constant.
    public static let defaultTagTintHex: String = "#7F8FA6"
}

/// Visual constants for the custom drag-reorder system in
/// `LillistUI/DragReorder/`. Adjust here, not at callsites.
public enum LillistDragTokens {
    /// Color of the active drop indicator (divider or row border).
    public static let indicatorColor: Color = .accentColor
    /// Border color drawn on the phantom row when the resolved target
    /// is `.rejected` (cycle).
    public static let rejectionColor: Color = Color.red.opacity(0.8)
    /// Thickness of the between-row divider when active.
    public static let dividerThickness: CGFloat = 2.5
    /// Stroke thickness of the onto-row border when active.
    public static let rowBorderThickness: CGFloat = 2.0
    /// Corner radius of the onto-row border highlight.
    public static let rowBorderCornerRadius: CGFloat = 8
    /// Outset of the onto-row border from the row's bounds, so the
    /// stroke does not visually overlap row content.
    public static let rowBorderOutset: CGFloat = 2
    /// Scale applied to the dragged-row phantom while *lifted* — i.e.
    /// during the active `.dragging` phase. The phantom inserts via a
    /// transition that animates from the natural scale (1.0) to this
    /// value, and the settle animation walks it back to 1.0.
    public static let phantomLiftedScale: CGFloat = 0.85
    /// Opacity applied to the dragged-row phantom while lifted.
    public static let phantomLiftedOpacity: Double = 0.70
    /// Shadow radius of the dragged-row phantom while lifted.
    public static let phantomShadowRadius: CGFloat = 12
    /// Vertical shadow offset of the dragged-row phantom while lifted.
    public static let phantomShadowYOffset: CGFloat = 8
    /// Duration of the lift animation on drag pickup (idle → dragging).
    public static let liftDuration: TimeInterval = 0.18
    /// Duration of the settle animation on drag release (dragging →
    /// dropping → idle). The phantom interpolates from lifted scale/
    /// opacity back to natural, and from `cursorY` to the resolved
    /// `settlePosition`, over this window.
    public static let settleDuration: TimeInterval = 0.22
    /// Long-press duration (iOS) before drag begins.
    public static let longPressDuration: TimeInterval = 0.3
    /// Max allowed finger drift during long-press before it cancels.
    public static let longPressMaxDistance: CGFloat = 4
    /// Horizontal inset of the between-row divider capsule, matching the
    /// list row's leading/trailing insets in `TasksScreen` so the divider
    /// aligns with row content.
    public static let dividerHorizontalInset: CGFloat = 12
}
