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
                    // i18n-exempt: user-authored Markdown.
                    Text(LocalizedStringKey(markdown))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .accessibilityLabel(String(localized: "Notes preview"))
            } else {
                TextEditor(text: $markdown)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(6) // TODO(Plan 14): replace with LillistSpacing.s
                    .overlay(
                        RoundedRectangle(cornerRadius: 6) // TODO(Plan 14): LillistRadius.s
                            .stroke(.quaternary)
                    )
                    .accessibilityLabel(String(localized: "Notes editor, Markdown"))
            }
        }
        .padding(.horizontal)
    }
}
