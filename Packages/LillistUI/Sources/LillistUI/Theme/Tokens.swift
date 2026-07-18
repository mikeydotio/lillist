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

/// Bounded sizes for self-sizing surfaces. The task editor is a floating
/// card that must **wrap its content** (like Quick Capture) rather than
/// fill the screen; these caps keep it compact while letting the growable
/// regions scroll in place once they exceed the cap. Width caps replace the
/// former inline `560`/`360` literals.
public enum LillistSizing {
    /// Full-mode detail card max width.
    public static let editorCardMaxWidth: CGFloat = 560
    /// Quick-capture card max width.
    public static let editorQuickMaxWidth: CGFloat = 360
    /// Drill-in child (schedule / attachments / journal) max height. The
    /// schedule `Form` is always bounded by it; the attachments/journal bodies
    /// use it only when there is no outer scroll (`EditorChildBody`) — under the
    /// overlay they hug and the overlay scrolls them.
    public static let editorChildMaxHeight: CGFloat = 400
    /// **macOS only:** max height of the macOS notes `TextEditor` before it
    /// scrolls in place, bounding its invisible sizer (which would otherwise grow
    /// unbounded). iOS notes grow with `.lineLimit(2...)` (no upper cap) and the
    /// overlay scrolls the card, so iOS does not use this token.
    public static let editorNotesMaxHeight: CGFloat = 200
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
    /// Thickness of the between-row divider when active.
    public static let dividerThickness: CGFloat = 2.5
    /// Scale applied to the dragged-row phantom while *lifted*. `1.0` = no
    /// shrink: the cell lifts at full size, with the shadow (not a resize) as
    /// the "picked up" cue. The settle machinery still interpolates this back
    /// to 1.0, so it remains a single tunable point if a shrink is reintroduced.
    public static let phantomLiftedScale: CGFloat = 1.0
    /// Opacity applied to the dragged-row phantom while lifted.
    public static let phantomLiftedOpacity: Double = 0.70
    /// Shadow radius of the dragged-row phantom while lifted —
    /// `LillistElevation.pop`'s key layer, kept as a single animatable
    /// shadow so the settle interpolation stays smooth.
    public static let phantomShadowRadius: CGFloat = 18
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
    /// Distance (pt) the macOS swipe `DragGesture` (`SwipeableRow`) travels
    /// before it commits to an axis via the shared `DragAxisArbiter`. Only a
    /// *horizontal* commit reveals a swipe action; a vertical commit is
    /// yielded to reorder/scroll. Sits one point past
    /// `macReorderAxisCommitDistance` (8) so a near-vertical drag commits to
    /// reorder first, keeping the two row gestures mutually exclusive. Also
    /// the swipe `DragGesture`'s `minimumDistance`, so the SwiftUI activation
    /// threshold and the arbiter's commit distance stay locked together.
    public static let macSwipeAxisCommitDistance: CGFloat = 10
    /// Horizontal inset of the between-row divider capsule, matching the
    /// list row's leading/trailing insets in `TasksScreen` so the divider
    /// aligns with row content.
    public static let dividerHorizontalInset: CGFloat = 12
    /// Leading indent applied per nesting level in the iOS outline
    /// (`TaskOutlineRowView`). Also the horizontal-drag sensitivity for
    /// depth disambiguation: dragging ~half this distance sideways shifts the
    /// drop one level. Single source of truth for both the row layout and the
    /// depth-aware drop indicator.
    public static let indentPerLevel: CGFloat = 22
    /// Per-level indent that macOS `OutlineGroup` applies to nested rows.
    /// Unlike iOS (which renders depth *inside* a full-width row),
    /// `OutlineGroup` shifts each row's frame, and the step is a system metric
    /// with no public API — this approximates it so the macOS drop indicator
    /// can render at the target depth. Tune on-device if it drifts.
    public static let macOutlineIndentPerLevel: CGFloat = 16
}
