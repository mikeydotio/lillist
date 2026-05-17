#if os(iOS)
import SwiftUI

/// Persistent floating "+" used across primary iOS surfaces.
///
/// Tap fires `onTap`. Long-press fires `onLongPress` (optional) — surfaces
/// "Quick Capture from clipboard" affordance in callers that want it.
public struct FloatingAddButton: View {
    public var onTap: () -> Void
    public var onLongPress: (() -> Void)?

    public init(onTap: @escaping () -> Void, onLongPress: (() -> Void)? = nil) {
        self.onTap = onTap
        self.onLongPress = onLongPress
    }

    public var body: some View {
        Button(action: onTap) {
            Image(systemName: "plus")
                .font(LillistTypography.floatingAddGlyph)
                .frame(width: LillistSpacing.xxl + LillistSpacing.l, height: LillistSpacing.xxl + LillistSpacing.l)  // 56pt
                .background {
                    Circle()
                        .fill(.tint)
                        .overlay(Circle().fill(.regularMaterial).opacity(0.15))
                }
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(String(localized: "New task", bundle: .module))
        .accessibilityHint(String(localized: "Opens quick capture", bundle: .module))
        .accessibilityAction(named: Text("Capture from clipboard")) {
            onLongPress?()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: LillistTiming.longPress).onEnded { _ in
                onLongPress?()
            }
        )
    }
}
#endif
