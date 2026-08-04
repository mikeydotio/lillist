import SwiftUI

/// The rainbow-bordered dark card frame shared by every widget surface —
/// `WidgetFilterCardView` (the task-list families) and, from `LIL-96`,
/// `WidgetStatusDonutView` (`.systemSmall`'s status composition). Extracted
/// verbatim from `WidgetFilterCardView` so both surfaces stay pixel-identical
/// without copy-pasting the frame math.
///
/// No Liquid Glass (it doesn't render in widgets): solid `LillistColor` fills +
/// a `RainbowGradient`-style angular border, which do render.
struct WidgetCardChrome: ViewModifier {
    /// Full-spectrum angular gradient for the border frame. The trailing purple
    /// closes the loop seamlessly (orange → purple).
    private static var frameGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: RainbowPalette.Spectrum.stops + [RainbowPalette.Spectrum.purple]),
            center: .center
        )
    }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // `ContainerRelativeShape` renders concentric with the widget's own
            // corner radius (which grew on iOS 26/27), so the card fill and the
            // rainbow border both hug the widget edge instead of a fixed radius
            // that would leave a visible corner gap. The inner fill, inset by
            // `.padding(4)`, stays concentric automatically.
            .background(ContainerRelativeShape().fill(LillistColor.card))
            .padding(4)
            .background(ContainerRelativeShape().fill(Self.frameGradient))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Wraps this view in the shared widget card frame: card fill, 4pt inset,
    /// rainbow angular-gradient border, edge-to-edge sizing.
    func widgetCardChrome() -> some View {
        modifier(WidgetCardChrome())
    }
}

/// The "nothing matches" state shared by every widget surface: a filled
/// checkmark in the `closed` status hue plus localized "All clear" text.
/// Promoted out of `WidgetFilterCardView` so `WidgetStatusDonutView`'s
/// `totalCount == 0` state renders the identical view, not a copy.
struct WidgetAllClearView: View {
    var body: some View {
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
