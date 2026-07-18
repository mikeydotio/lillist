// Cross-platform: shared by the iOS app and the macOS main window.
import SwiftUI

/// Whether the task editor is hosted inside an outer scroll container (the
/// `taskEditorOverlay`'s `editorScrollAndCenter`). Child popups read this to
/// decide whether they may hug their content (an outer scroll handles overflow)
/// or must self-bound and scroll internally (no outer scroll — e.g. the macOS
/// hotkey `NSPanel`, which sizes itself to the editor's intrinsic height and
/// would otherwise clip a tall child).
///
/// Default is **`false`** on purpose: the never-clips, self-bounding branch is
/// the safe fallback, so any host that forgets to opt in still renders
/// correctly. Only the overlay's `editorScrollAndCenter` flips it to `true`.
private struct EditorHasOuterScrollKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// See `EditorHasOuterScrollKey`. Set by `editorScrollAndCenter`.
    var editorHasOuterScroll: Bool {
        get { self[EditorHasOuterScrollKey.self] }
        set { self[EditorHasOuterScrollKey.self] = newValue }
    }
}

public extension View {
    /// Host the task editor so it **centers when it fits** the offered
    /// (keyboard-aware) height and **scrolls when it overflows** — the single
    /// scroll owner for the whole card. Because the card sizes itself
    /// synchronously (a plain VStack), no measurement is needed: the frame
    /// resolves to `max(viewport, content)` in one layout pass.
    ///
    /// The scroll lives *here*, at the overlay, not inside `TaskEditorView`: the
    /// macOS hotkey `NSPanel` host sizes itself to the editor's intrinsic height,
    /// which a `GeometryReader`/`ScrollView` inside the card would defeat.
    ///
    /// - Parameter onBackgroundTap: fired by a tap in the gutters around the
    ///   card (dismiss). Taps on the card itself are swallowed, so a tap on a
    ///   glass gap between controls does not dismiss.
    func editorScrollAndCenter(onBackgroundTap: @escaping () -> Void = {}) -> some View {
        modifier(EditorScrollAndCenter(onBackgroundTap: onBackgroundTap))
    }
}

/// The center-or-scroll container. See `editorScrollAndCenter(onBackgroundTap:)`.
private struct EditorScrollAndCenter: ViewModifier {
    var onBackgroundTap: () -> Void

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content
                    // The card swallows taps on its own bounds (including the
                    // translucent gaps between controls, which the glass
                    // `.background` does not hit-test) so a tap on the card never
                    // dismisses — only the gutters do (the fill layer below).
                    .contentShape(RoundedRectangle(cornerRadius: LillistRadius.l, style: .continuous))
                    .onTapGesture {}
                    .padding(.horizontal, LillistSpacing.l)
                    .padding(.vertical, LillistSpacing.xl)
                    // `minHeight == viewport` centers the card when it fits and
                    // lets the ScrollView top-anchor + scroll when it overflows.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                    // A clear fill behind the card: taps in the gutters (outside
                    // the card's contentShape) land here and dismiss; drags scroll.
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { onBackgroundTap() }
                    }
            }
            // Passive while the card fits (quick mode, a short full card): keeps
            // the card centered and stationary rather than rubber-banding.
            .scrollBounceBehavior(.basedOnSize)
        }
        .environment(\.editorHasOuterScroll, true)
    }
}
