import SwiftUI
import LillistUI

/// Driver layer that hosts `FloatingAddButton` and toggles `isPresented`.
/// Hidden via opacity when the system keyboard is up — it'd be invisible
/// behind the keyboard anyway, and hiding it from accessibility prevents
/// VoiceOver from snagging on an off-screen button.
struct FloatingPlusOverlay: View {
    @Binding var isPresented: Bool
    @State private var keyboardVisible = false

    var body: some View {
        FloatingAddButton(onTap: { isPresented = true })
            .opacity(keyboardVisible ? 0 : 1)
            .accessibilityHidden(keyboardVisible)
            .onReceive(
                NotificationCenter.default
                    .publisher(for: UIResponder.keyboardWillShowNotification)
            ) { _ in keyboardVisible = true }
            .onReceive(
                NotificationCenter.default
                    .publisher(for: UIResponder.keyboardWillHideNotification)
            ) { _ in keyboardVisible = false }
    }
}
