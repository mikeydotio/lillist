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
