import SwiftUI

struct JournalComposerView: View {
    @Environment(AppEnvironment.self) private var env
    let taskID: UUID
    var onAdded: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 4) {
            TextEditor(text: $text)
                .frame(minHeight: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                .accessibilityLabel(String(localized: "Journal composer; drag files or paste URLs"))
            HStack {
                Spacer()
                Button("Add entry") { Task { await submit() } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private func submit() async {
        let body = text
        text = ""
        _ = try? await env.journalStore.appendNote(taskID: taskID, body: body)
        onAdded()
    }
}
