#if os(iOS)
import SwiftUI

extension View {
    /// Shared Rainbow Glass toast chrome: a Liquid Glass capsule on
    /// OS 26 (degrading to `.regularMaterial`, then an opaque fallback
    /// under Reduce Transparency on older OS — see `GlassSurface`), a
    /// hairline border, and floating-bar separation that yields to the
    /// glass on OS 26 and falls back to the `lift` shadow below it. One
    /// modifier so the four toasts (archive, reorder-failure,
    /// status-failure, capture-discard) can't drift apart.
    ///
    /// Co-visible toasts must be wrapped in a `glassGroup()` by the host
    /// so the glass capsules don't sample one another.
    func rainbowToastChrome() -> some View {
        glassSurface(.toast, in: Capsule())
            .overlay(Capsule().strokeBorder(LillistColor.borderHair, lineWidth: 1))
            .glassElevation(.lift)
    }
}
#endif
