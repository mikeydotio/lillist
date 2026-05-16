#if os(iOS)
import SwiftUI

/// Single-line text field used by Quick Capture and inline create on iOS.
///
/// Recognizes `#tag` and `^date phrase` tokens and surfaces tappable
/// autocomplete chips below the field. Submission emits a parsed
/// `QuickCaptureParser.Result` — the same parser the macOS Quick Capture
/// surface uses, so the two platforms stay aligned.
public struct QuickCaptureField: View {
    @Binding var text: String
    var tagSuggestions: [String]
    var dateSuggestions: [String]
    var onSubmit: (QuickCaptureParser.Result) -> Void

    public init(
        text: Binding<String>,
        tagSuggestions: [String] = [],
        dateSuggestions: [String] = [],
        onSubmit: @escaping (QuickCaptureParser.Result) -> Void
    ) {
        self._text = text
        self.tagSuggestions = tagSuggestions
        self.dateSuggestions = dateSuggestions
        self.onSubmit = onSubmit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Capture a task…", text: $text)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .accessibilityIdentifier("QuickCaptureField")
                .onSubmit {
                    onSubmit(QuickCaptureParser.parse(text))
                }
            if !tagSuggestions.isEmpty || !dateSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tagSuggestions, id: \.self) { tag in
                            Button {
                                text += " #\(tag)"
                            } label: {
                                Text("#\(tag)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert tag \(tag)")
                        }
                        ForEach(dateSuggestions, id: \.self) { phrase in
                            Button {
                                text += " ^\(phrase)"
                            } label: {
                                Text("^\(phrase)")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .frame(minHeight: 44)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert deadline \(phrase)")
                        }
                    }
                }
            }
        }
    }
}
#endif
