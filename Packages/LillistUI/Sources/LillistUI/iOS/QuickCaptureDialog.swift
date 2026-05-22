#if os(iOS)
import SwiftUI

/// Centered Spotlight-style dialog for iOS Quick Capture.
///
/// Pure presentation — no `@State`, no environment reads, no async
/// work. Hosts pass `text` as a binding, an optional `errorMessage`,
/// and an `onSubmit` closure invoked when the user presses Return on a
/// non-empty editor.
///
/// Renders the same `QuickCaptureParser` token chips the macOS panel
/// uses, so the two surfaces stay aligned. The footer legend fades to a
/// quieter opacity once the user types — the contract is loud while it
/// matters and recedes once the user clearly knows what to do.
public struct QuickCaptureDialog: View {
    @Binding public var text: String
    public var errorMessage: String?
    public var onSubmit: () -> Void
    @FocusState private var focused: Bool

    public init(
        text: Binding<String>,
        errorMessage: String? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
    }

    public var body: some View {
        let parsed = QuickCaptureParser.parse(text)
        VStack(alignment: .leading, spacing: LillistSpacing.m) {
            TextField("Capture a task…", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(LillistTypography.quickCaptureField)
                .submitLabel(.done)
                .focused($focused)
                .accessibilityIdentifier("QuickCaptureField")
                .onSubmit {
                    focused = false
                    onSubmit()
                }
                .onAppear { focused = true }

            if !parsed.tags.isEmpty || parsed.dateToken != nil {
                HStack(spacing: LillistSpacing.xs + 2) {
                    ForEach(parsed.tags, id: \.self) { name in
                        TagChipView(name: name)
                    }
                    if let token = parsed.dateToken {
                        Label(token, systemImage: "calendar")
                            .font(LillistTypography.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(
                                String(
                                    localized: "Parsed deadline \(token)",
                                    bundle: .module
                                )
                            )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Return to save · tap outside to cancel")
                Text("#tag · ^date")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .opacity(text.isEmpty ? 1.0 : 0.55)
            .accessibilityHidden(true)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(LillistTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 360)
        .accessibleMaterial(
            .regularMaterial,
            fallback: Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: LillistRadius.m)
        )
    }
}
#endif
