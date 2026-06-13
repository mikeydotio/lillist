#if os(iOS)
import SwiftUI

/// Transient "Discarded · Undo" pill shown when the user tap-outsides
/// the Quick Capture dialog with text already typed.
///
/// Auto-dismisses ~4 seconds after appearing; tapping Undo fires
/// `onUndo` (which the host wires to "restore the text and re-present
/// the dialog") and dismisses immediately. Bottom safe-area anchored —
/// the consumer is expected to attach this as an overlay with
/// `.overlay(alignment: .bottom) { QuickCaptureDiscardToast(...) }`.
public struct QuickCaptureDiscardToast: View {
    @Binding public var isPresented: Bool
    public var onUndo: () -> Void

    public init(isPresented: Binding<Bool>, onUndo: @escaping () -> Void) {
        self._isPresented = isPresented
        self.onUndo = onUndo
    }

    public var body: some View {
        Group {
            if isPresented {
                HStack(spacing: LillistSpacing.s) {
                    Text(String(localized: "Discarded", bundle: .module))
                        .foregroundStyle(.primary)
                    Button {
                        onUndo()
                        isPresented = false
                    } label: {
                        Text(String(localized: "Undo", bundle: .module))
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(
                        String(localized: "Undo discard", bundle: .module)
                    )
                }
                .font(LillistTypography.body)
                .padding(.horizontal, LillistSpacing.l)
                .padding(.vertical, LillistSpacing.m)
                .rainbowToastChrome()
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
