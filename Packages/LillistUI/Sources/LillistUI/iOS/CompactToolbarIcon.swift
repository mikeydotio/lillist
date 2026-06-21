#if os(iOS)
import SwiftUI

/// Shrinks a navigation-toolbar SF Symbol to a compact size while leaving
/// the system's 44pt hit target untouched.
///
/// On iOS 26 the Liquid Glass toolbar capsule sizes itself to its content
/// (plus a system minimum), so a smaller glyph yields a visibly smaller
/// chip without us reaching into the system-owned glass. `@ScaledMetric`
/// keeps the glyph responsive to Dynamic Type: ~30% under the ~17pt
/// system-default toolbar glyph at the standard content size, and it still
/// grows with the user's preferred text size.
struct CompactToolbarIcon: ViewModifier {
    /// ~30% smaller than the ~17pt system-default toolbar glyph.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 12

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .regular))
    }
}

extension View {
    /// Renders a toolbar SF Symbol ~30% smaller than the system default.
    ///
    /// Apply to the icon `label` of a toolbar `Button`/`Menu`. The system
    /// keeps the surrounding 44pt hit target; only the visible glyph — and
    /// therefore the glass chip hugging it — shrinks.
    func compactToolbarIcon() -> some View {
        modifier(CompactToolbarIcon())
    }
}
#endif
