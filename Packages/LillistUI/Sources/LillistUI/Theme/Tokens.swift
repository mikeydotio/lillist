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
/// Rainbow Logic values: soft, pill-friendly, tactile. Use the
/// `.continuous` corner style with these. Capsule shapes use
/// `Capsule`, not a radius token.
public enum LillistRadius {
    public static let s: CGFloat = 8
    /// Default card/field radius.
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    /// Large floating surfaces.
    public static let xl: CGFloat = 22
    /// The 3D status cube (`StatusCubeView`).
    public static let cube: CGFloat = 8
}

/// Gesture-timing constants. `longPress` is the duration we expect a
/// user to hold before a long-press-bound action fires. Used by
/// `StatusIndicatorView` and `FloatingAddButton`.
public enum LillistTiming {
    public static let longPress: TimeInterval = 0.4
}

/// Semantic typography: Plus Jakarta Sans at the Rainbow Logic scale.
/// Every token is `relativeTo:` a Dynamic Type text style, so user
/// accessibility text-size settings keep scaling chrome text — never
/// reintroduce a frozen `.font(.system(size: N))`. If font
/// registration fails (`LillistFonts`), tokens fall back to the
/// system style they are relative to.
public enum LillistTypography {
    /// Onboarding heroes, splash screens.
    public static let largeTitle: Font = jakarta("ExtraBold", 30, relativeTo: .largeTitle, fallback: .largeTitle)
    /// Major headings.
    public static let title: Font = jakarta("Bold", 24, relativeTo: .title, fallback: .title)
    /// Sheet headers like the onboarding "Welcome to Lillist".
    public static let title2: Font = jakarta("Bold", 20, relativeTo: .title2, fallback: .title2)
    /// Secondary headings, sub-section titles.
    public static let title3: Font = jakarta("SemiBold", 17, relativeTo: .title3, fallback: .title3)
    /// Emphasized body: task-row titles, sidebar group labels.
    public static let headline: Font = jakarta("SemiBold", 15, relativeTo: .headline, fallback: .headline)
    /// Default text in most form rows.
    public static let body: Font = jakarta("Regular", 15, relativeTo: .body, fallback: .body)
    /// Captions under titles, supporting text.
    public static let subheadline: Font = jakarta("Medium", 13, relativeTo: .subheadline, fallback: .subheadline)
    /// Small descriptive labels (tag chips, badges, due dates).
    public static let caption: Font = jakarta("SemiBold", 11.5, relativeTo: .caption, fallback: .caption)
    /// Date/time stamps in journal rows.
    public static let caption2: Font = jakarta("Medium", 11, relativeTo: .caption2, fallback: .caption2)
    /// Quick-capture field text.
    public static let quickCaptureField: Font = jakarta("SemiBold", 17, relativeTo: .title3, fallback: .title3)
    /// `RainbowButtonStyle` label, small size.
    public static let buttonSm: Font = jakarta("Bold", 13, relativeTo: .subheadline, fallback: .subheadline.bold())
    /// `RainbowButtonStyle` label, medium size.
    public static let buttonMd: Font = jakarta("Bold", 15, relativeTo: .body, fallback: .body.bold())
    /// Floating add button "+" glyph (SF Symbol, stays system).
    public static let floatingAddGlyph: Font = .title.weight(.semibold)

    /// Plus Jakarta Sans face scaled relative to a Dynamic Type style,
    /// falling back to the plain text style when registration fails.
    private static func jakarta(
        _ weight: String, _ size: CGFloat,
        relativeTo style: Font.TextStyle, fallback: Font
    ) -> Font {
        LillistFonts.registerIfNeeded()
            ? .custom("\(LillistFonts.familyStem)-\(weight)", size: size, relativeTo: style)
            : fallback
    }
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
    /// Focus-blue: drag targeting is "work in flight" in the Rainbow
    /// Logic functional-color language.
    public static let indicatorColor: Color = RainbowPalette.focusBlue.base
    /// Border color drawn on the phantom row when the resolved target
    /// is `.rejected` (cycle). Deep action-orange — the urgent hue —
    /// replaces the old red (Rainbow Logic has no red).
    public static let rejectionColor: Color = RainbowPalette.actionOrange.deep.opacity(0.85)
    /// Thickness of the between-row divider when active.
    public static let dividerThickness: CGFloat = 2.5
    /// Stroke thickness of the onto-row border when active.
    public static let rowBorderThickness: CGFloat = 2.0
    /// Corner radius of the onto-row border highlight. Matches the
    /// Rainbow card radius (`LillistRadius.m`) so the highlight hugs
    /// the card.
    public static let rowBorderCornerRadius: CGFloat = 12
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
    /// Shadow radius of the dragged-row phantom while lifted —
    /// `LillistElevation.pop`'s key layer, kept as a single animatable
    /// shadow so the settle interpolation stays smooth.
    public static let phantomShadowRadius: CGFloat = 18
    /// Opacity of the rainbow halo stroked around the lifted phantom
    /// (the one place the halo appears on iPhone).
    public static let phantomHaloOpacity: Double = 0.5
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
    /// Distance (pt) the macOS reorder `DragGesture` travels before it
    /// commits to an axis. Only *vertical*-committed drags begin a reorder;
    /// horizontal drags are yielded to the row's swipe gesture
    /// (`SwipeableRow`). Sits between the reorder gesture's 4 pt
    /// `minimumDistance` and the swipe gesture's 10 pt commit, so reorder
    /// claims a vertical drag a touch before the swipe would react.
    public static let macReorderAxisCommitDistance: CGFloat = 8
    /// Horizontal inset of the between-row divider capsule, matching the
    /// list row's leading/trailing insets in `TasksScreen` so the divider
    /// aligns with row content.
    public static let dividerHorizontalInset: CGFloat = 12
}
