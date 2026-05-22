#if os(iOS)
import SwiftUI

public extension View {
    /// Present a centered, upper-third-anchored dialog over this view.
    ///
    /// Renders a dim backdrop that dismisses the dialog when tapped, a
    /// scale + opacity entry transition (opacity-only under Reduce
    /// Motion), and an Esc key handler for hardware keyboards. The
    /// `onCancel` closure fires *before* `isPresented` is flipped to
    /// false on either tap-outside or Esc, so hosts can capture the
    /// current text for an Undo affordance.
    ///
    /// Successful save paths (the dialog's own Return handler)
    /// should flip `isPresented = false` directly — `onCancel` is not
    /// invoked on save.
    func quickCaptureDialog<DialogContent: View>(
        isPresented: Binding<Bool>,
        onCancel: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> DialogContent
    ) -> some View {
        modifier(QuickCaptureDialogPresenter(
            isPresented: isPresented,
            onCancel: onCancel,
            dialogContent: content
        ))
    }
}

private struct QuickCaptureDialogPresenter<DialogContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onCancel: () -> Void
    @ViewBuilder var dialogContent: () -> DialogContent

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion

    private var reduceMotion: Bool {
        overrideReduceMotion ?? systemReduceMotion
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                            .onTapGesture {
                                onCancel()
                                isPresented = false
                            }
                            .transition(.opacity)

                        dialogContent()
                            .padding(.top, 80)
                            .padding(.horizontal, LillistSpacing.xl)
                            .ignoresSafeArea(.keyboard)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(
                                        with: .scale(scale: 0.96, anchor: .top)
                                    )
                            )
                            .onKeyPress(.escape) {
                                onCancel()
                                isPresented = false
                                return .handled
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
