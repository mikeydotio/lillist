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
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(radius: 6, y: 3)
        }
        .accessibilityLabel("New task")
        .accessibilityHint("Opens quick capture")
        .accessibilityAction(named: Text("Capture from clipboard")) {
            onLongPress?()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                onLongPress?()
            }
        )
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}
#endif
