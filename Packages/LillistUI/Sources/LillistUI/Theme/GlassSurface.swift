import SwiftUI

/// The single integration seam for Apple's Liquid Glass material in the
/// "Rainbow Glass" design system.
///
/// Rainbow Glass replaces the hand-rolled depth cues of the original
/// Rainbow Logic system (`rainbowShadow` two-layer drop shadows,
/// `RainbowTopHighlight` inset highlights, inset-well gradients, the
/// isometric `StatusCubeView`) with the real adaptive material that
/// produces refraction, specular highlight, contact shadow, and motion
/// response natively. The whimsical rainbow palette survives as
/// *functional* glass tints — never decoration.
///
/// **Why one seam.** Every glass call routes through `glassSurface(_:in:)`
/// so three concerns live in exactly one file:
///   1. **Availability.** Liquid Glass is iOS 26 / macOS 26. The iOS app
///      floor is already 26; the macOS app floor is still 15 (Sequoia).
///      The `#available` gate is centralized here so call-sites never see
///      a guard and Sequoia keeps the previous Material look for free.
///   2. **Degradation.** Liquid Glass (OS 26) → `.regularMaterial` (older
///      OS) → opaque color (Reduce Transparency, *older OS only*). On
///      OS 26 the glass renderer self-handles Reduce Transparency, so we
///      deliberately do **not** double-handle it.
///   3. **The dark-mode workaround.** If the SDK's dark-mode glass
///      rendering needs pinning, this is the one place to do it.
///
/// House rules preserved: color is functional (tints map to meaning,
/// never decoration); neutral glass (`.regular`, untinted) for
/// non-semantic chrome; glass goes on the floating control layer and the
/// signature components — repeating content rows are gated on a perf/
/// legibility spike (see the Rainbow Glass plan).
public enum GlassSurface: Sendable, Equatable {
    /// A neutral floating bar or panel: the filter header background, the
    /// quick-capture panel. Untinted `.regular` glass.
    case panel
    /// A transient toast capsule (archive, reorder, status, capture
    /// discard). Untinted `.regular` glass with a hairline border.
    case toast
    /// A plain neutral control with no functional tint.
    case control
    /// A content-layer card surface. Use only where the Wave 0 spike
    /// confirms per-surface glass holds up on perf and legibility.
    case card
    /// A surface tinted by a functional status hue (e.g. the status
    /// element). Pass the hue's `base` fill color.
    case statusTinted(Color)

    /// Whether the pre-26 fallback is a solid color rather than
    /// `.regularMaterial`. True for tinted *fills* (the FAB, status
    /// chips, cards) that were never frosted chrome — on a pre-26 OS
    /// like macOS Sequoia they must stay solid, not turn translucent.
    /// False for genuine chrome (panels, toasts) that *was* material.
    var prefersSolidFallback: Bool {
        switch self {
        case .statusTinted, .card, .control: true
        case .panel, .toast: false
        }
    }

    /// Material used on pre-26 OS for the chrome roles
    /// (`prefersSolidFallback == false`).
    var material: Material {
        .regularMaterial
    }

    /// Opaque surface used under Reduce Transparency on pre-26 OS. (On
    /// OS 26 the glass renderer handles Reduce Transparency itself.)
    var opaqueFallback: AnyShapeStyle {
        switch self {
        case .toast, .control, .card:
            AnyShapeStyle(LillistColor.card)
        case .panel:
            AnyShapeStyle(LillistColor.workspace)
        case .statusTinted(let color):
            AnyShapeStyle(color)
        }
    }

    /// Functional tint applied to OS-26 glass, or `nil` for neutral glass.
    var tint: Color? {
        switch self {
        case .statusTinted(let color):
            color
        case .panel, .toast, .control, .card:
            nil
        }
    }
}

public extension View {
    /// Apply a Liquid Glass control-layer surface with full degradation:
    /// Liquid Glass (OS 26) → `.regularMaterial` (older OS) → opaque
    /// color (Reduce Transparency, older OS only).
    ///
    /// The default shape is a `Capsule`, matching the system's own glass
    /// default. Pass a `RoundedRectangle(cornerRadius:style:.continuous)`
    /// for panels and cards.
    func glassSurface(_ surface: GlassSurface, in shape: some Shape = Capsule()) -> some View {
        modifier(GlassSurfaceModifier(surface: surface, shape: AnyShape(shape)))
    }

    /// Group sibling glass surfaces so they blend/merge correctly and do
    /// not sample one another (Liquid Glass cannot sample other glass).
    /// No-op below OS 26. Wrap any region where two glass surfaces can be
    /// simultaneously visible or overlapping — e.g. stacked toasts, or a
    /// morphing control pair.
    @ViewBuilder
    func glassGroup(spacing: CGFloat? = nil) -> some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
    }

    /// Elevation that yields to glass on OS 26 (the material carries its
    /// own separation, so stacking a hand-rolled shadow on top reads
    /// muddy — especially in dark mode) and falls back to the Rainbow
    /// Logic two-layer shadow below 26. This is how the shadow system
    /// "retires" without dropping pre-26 fidelity.
    @ViewBuilder
    func glassElevation(_ fallback: LillistElevation) -> some View {
        if #available(iOS 26, macOS 26, *) {
            self
        } else {
            rainbowShadow(fallback)
        }
    }
}

private struct GlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.reduceTransparencyOverride) private var overrideReduceTransparency
    let surface: GlassSurface
    let shape: AnyShape

    func body(content: Content) -> some View {
        // OS 26: real Liquid Glass. It self-handles Reduce Transparency
        // inside the renderer, so we do NOT branch on it here — branching
        // would double-handle and fight the system's tuned behavior.
        if #available(iOS 26, macOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            // Pre-26: solid color for tinted fills (and under Reduce
            // Transparency); `.regularMaterial` for genuine chrome.
            let reduce = overrideReduceTransparency ?? systemReduceTransparency
            if surface.prefersSolidFallback || reduce {
                content.background(surface.opaqueFallback, in: shape)
            } else {
                content.background(surface.material, in: shape)
            }
        }
    }

    @available(iOS 26, macOS 26, *)
    private var glass: Glass {
        var resolved: Glass = .regular
        if let tint = surface.tint {
            resolved = resolved.tint(tint)
        }
        return resolved
    }
}
