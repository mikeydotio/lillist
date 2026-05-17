import SwiftUI

/// A text field whose Return creates a sibling, Tab indents, Shift-Tab outdents.
/// The owning view supplies the three callbacks; this view stays presentation-only.
struct InlineCreateField: View {
    @Binding var text: String
    var onReturn: () -> Void
    var onTab: () -> Void
    var onShiftTab: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("New task", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .onSubmit { onReturn() }
            .onAppear { focused = true }
            #if os(macOS)
            .onExitCommand(perform: onCancel)
            #endif
            .onKeyPress(keys: [.tab], phases: .down) { press in
                if text.isEmpty {
                    return .ignored
                }
                if press.modifiers.contains(.shift) {
                    onShiftTab()
                } else {
                    onTab()
                }
                return .handled
            }
            .accessibilityLabel(String(localized: "New task title; Return to save, Tab to indent"))
    }
}
