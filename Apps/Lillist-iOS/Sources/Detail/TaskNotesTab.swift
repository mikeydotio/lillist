import SwiftUI
import LillistCore

/// Notes tab: free-text editor backed by `TaskStore.update`. Writes are
/// debounced through a `.task(id: text)` 500ms wait — SwiftUI cancels
/// the pending task when text changes, so only the last edit in a
/// typing burst hits Core Data + CloudKit. Save also runs on focus
/// loss so a segment switch flushes state before the view tears down.
struct TaskNotesTab: View {
    static let debounceMilliseconds: UInt64 = 500

    let taskID: UUID
    let initialText: String
    @Environment(AppEnvironment.self) private var env

    @State private var text: String = ""
    @State private var hasAppeared = false
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .padding(.horizontal)
            .accessibilityLabel(String(localized: "Notes"))
            .focused($focused)
            .onAppear {
                guard !hasAppeared else { return }
                text = initialText
                hasAppeared = true
            }
            .task(id: text) {
                guard hasAppeared else { return }
                do {
                    try await Task.sleep(for: .milliseconds(Int(Self.debounceMilliseconds)))
                } catch {
                    return  // cancelled — newer keystroke arrived
                }
                await saveNotes(text)
            }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused, hasAppeared else { return }
                Task { await saveNotes(text) }
            }
    }

    private func saveNotes(_ value: String) async {
        try? await env.taskStore.update(id: taskID) { draft in
            draft.notes = value
        }
    }
}
