// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

public extension View {
    /// Present the unified task editor as a centered, dim-backed floating
    /// card. Like `quickCaptureDialog` but keyboard-aware (the card lifts
    /// above the keyboard rather than ignoring it) so `full` mode's many
    /// fields stay reachable. Tap-outside and Esc fire `onCancel` before
    /// dismissing; committed dismissals flip `isPresented` directly.
    func taskEditorOverlay<EditorContent: View>(
        isPresented: Binding<Bool>,
        onCancel: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> EditorContent
    ) -> some View {
        modifier(TaskEditorOverlay(isPresented: isPresented, onCancel: onCancel, editorContent: content))
    }
}

private struct TaskEditorOverlay<EditorContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onCancel: () -> Void
    @ViewBuilder var editorContent: () -> EditorContent

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var overrideReduceMotion
    private var reduceMotion: Bool { overrideReduceMotion ?? systemReduceMotion }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                            .onTapGesture {
                                onCancel()
                                isPresented = false
                            }
                            .transition(.opacity)

                        editorContent()
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                            )
                            .onKeyPress(.escape) {
                                onCancel()
                                isPresented = false
                                return .handled
                            }
                            // The single scroll owner: the card centers when it
                            // fits the (keyboard-aware) offer and scrolls when it
                            // overflows. The card's own padding now lives here.
                            .editorScrollAndCenter(onBackgroundTap: {
                                onCancel()
                                isPresented = false
                            })
                    }
                }
            }
            .accessibleAnimation(
                .spring(response: 0.32, dampingFraction: 0.85),
                value: isPresented
            )
    }
}
