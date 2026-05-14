import SwiftUI

struct NotesEditorView: View {
    @Binding var markdown: String
    @State private var previewing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notes").font(.headline)
                Spacer()
                Toggle("Preview", isOn: $previewing)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            if previewing {
                ScrollView {
                    Text(LocalizedStringKey(markdown))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .accessibilityLabel("Notes preview")
            } else {
                TextEditor(text: $markdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .accessibilityLabel("Notes editor, Markdown")
            }
        }
        .padding(.horizontal)
    }
}
