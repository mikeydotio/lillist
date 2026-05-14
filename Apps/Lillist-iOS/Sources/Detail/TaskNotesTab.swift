import SwiftUI
import LillistCore

/// Notes tab: free-text editor backed by `TaskStore.update`.
struct TaskNotesTab: View {
    let taskID: UUID
    let initialText: String
    @Environment(AppEnvironment.self) private var env

    @State private var text: String = ""
    @State private var hasAppeared = false

    var body: some View {
        VStack {
            TextEditor(text: $text)
                .padding(.horizontal)
                .accessibilityLabel("Notes")
        }
        .onAppear {
            guard !hasAppeared else { return }
            text = initialText
            hasAppeared = true
        }
        .onChange(of: text) { _, newValue in
            Task {
                try? await env.taskStore.update(id: taskID) { draft in
                    draft.notes = newValue
                }
            }
        }
    }
}
