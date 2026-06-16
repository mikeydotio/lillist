#if os(iOS)
import SwiftUI

/// Centered Spotlight-style dialog for iOS Quick Capture.
///
/// Presentation-only — no `@State` of its own beyond focus, no async
/// work, no `AppEnvironment` coupling (the accessibility-contrast reads
/// below are the same passive environment reads `StatusCubeView` uses).
/// Hosts pass `text` as a binding, an optional `errorMessage`, and an
/// `onSubmit` closure invoked from Return or the Add button on a
/// non-empty editor.
///
/// The field is the same inset-well language as the filter search bar —
/// a sunken `rainbowWell` at rest that lifts to a focus-blue ring while
/// editing — and the syntax hint lives in the placeholder rather than a
/// help-doc legend. A single quiet "Return to save" contract recedes
/// once the user types; the signature lavender Add button is the
/// primary action. Renders the same `QuickCaptureParser` token chips
/// the macOS panel uses, so the two surfaces stay aligned.
public struct QuickCaptureDialog: View {
    @Binding public var text: String
    public var errorMessage: String?
    public var onSubmit: () -> Void
    @FocusState private var focused: Bool

    @Environment(\.accessibilityShouldIncreaseContrast) private var systemIncreaseContrast
    @Environment(\.increaseContrastOverride) private var overrideIncreaseContrast

    public init(
        text: Binding<String>,
        errorMessage: String? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
    }

    private var increaseContrast: Bool {
        overrideIncreaseContrast ?? systemIncreaseContrast
    }

    public var body: some View {
        let parsed = QuickCaptureParser.parse(text)
        let trimmedTitle = parsed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: LillistSpacing.m) {
            captureField

            if !parsed.tags.isEmpty || parsed.dateToken != nil {
                HStack(spacing: LillistSpacing.xs + 2) {
                    ForEach(parsed.tags, id: \.self) { name in
                        TagChipView(name: name)
                    }
                    if let token = parsed.dateToken {
                        Label(token, systemImage: "calendar")
                            .font(LillistTypography.caption)
                            .foregroundStyle(LillistColor.textMuted)
                            .accessibilityLabel(
                                String(
                                    localized: "Parsed deadline \(token)",
                                    bundle: .module
                                )
                            )
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(LillistTypography.caption)
                    .foregroundStyle(RainbowPalette.actionOrange.ink)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack(spacing: LillistSpacing.s) {
                Text("Return to save", bundle: .module)
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textFaint)
                    .opacity(text.isEmpty ? 1 : 0)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button {
                    focused = false
                    onSubmit()
                } label: {
                    Text("Add", bundle: .module)
                }
                .buttonStyle(.rainbow(.lavender, size: .sm))
                .disabled(trimmedTitle.isEmpty)
                .accessibilityIdentifier("QuickCaptureAddButton")
            }
        }
        .padding(LillistSpacing.l)
        .frame(maxWidth: 360)
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.l))
    }

    /// The sunken capture field, mirroring `FilterHeader`'s search well:
    /// `rainbowWell` at rest, lifting to a `card` fill + focus-blue ring
    /// while editing. The syntax hint rides in the prompt.
    private var captureField: some View {
        TextField(
            text: $text,
            prompt: Text("Capture a task…  #tag ^date", bundle: .module)
        ) {
            Text("New task", bundle: .module)
        }
        .textFieldStyle(.plain)
        .font(LillistTypography.quickCaptureField)
        .foregroundStyle(LillistColor.textStrong)
        .submitLabel(.done)
        .focused($focused)
        .accessibilityIdentifier("QuickCaptureField")
        .onSubmit {
            focused = false
            onSubmit()
        }
        .onAppear { focused = true }
        .padding(.horizontal, LillistSpacing.m)
        .padding(.vertical, LillistSpacing.s + 2)
        .background {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .fill(focused ? AnyShapeStyle(LillistColor.card) : .rainbowWell)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                .strokeBorder(
                    focused
                        ? RainbowPalette.focusBlue.base.opacity(0.35)
                        : (increaseContrast ? LillistColor.borderStrong : LillistColor.borderHair),
                    lineWidth: focused ? 2 : 1
                )
        }
    }
}
#endif
