#if os(iOS)
import SwiftUI

extension View {
    /// Shared Rainbow Logic toast chrome: frosted capsule (existing
    /// `accessibleMaterial` Reduce-Transparency contract, with the
    /// fallback now `LillistColor.card`), hairline border, and the
    /// floating-bar `lift` shadow. One modifier so the four toasts
    /// (archive, reorder-failure, status-failure, capture-discard)
    /// can't drift apart.
    func rainbowToastChrome() -> some View {
        accessibleMaterial(.regularMaterial, fallback: LillistColor.card, in: Capsule())
            .overlay(Capsule().strokeBorder(LillistColor.borderHair, lineWidth: 1))
            .rainbowShadow(.lift)
    }
}
#endif
