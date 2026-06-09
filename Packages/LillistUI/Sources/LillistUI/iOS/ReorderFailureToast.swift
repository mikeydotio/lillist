#if os(iOS)
import SwiftUI

/// Transient "Couldn't move that item. Please try again." pill shown when
/// a drag-reorder write fails (e.g. stale anchor after a CloudKit merge).
///
/// Auto-dismisses after ~4 seconds. No undo action — the failure is
/// transient and the list is reloaded automatically. Bottom safe-area
/// anchored — attach as `.overlay(alignment: .bottom) { ReorderFailureToast(...) }`.
public struct ReorderFailureToast: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        Group {
            if isPresented {
                Text(String(
                    localized: "Couldn't move that item. Please try again.",
                    bundle: .module
                ))
                .font(LillistTypography.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, LillistSpacing.l)
                .padding(.vertical, LillistSpacing.m)
                .accessibleMaterial(
                    .regularMaterial,
                    fallback: Color(uiColor: .secondarySystemBackground),
                    in: Capsule()
                )
                .padding(.bottom, LillistSpacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: isPresented) {
                    guard isPresented else { return }
                    try? await Task.sleep(for: .seconds(4))
                    if !Task.isCancelled, isPresented {
                        isPresented = false
                    }
                }
            }
        }
        .accessibleAnimation(
            .spring(response: 0.32, dampingFraction: 0.85),
            value: isPresented
        )
    }
}
#endif
