import SwiftUI

/// The borderless single-field UI shown by the macOS global hotkey.
/// Hosted in an NSPanel by the app target; pure-SwiftUI here for snapshot testing.
public struct QuickCaptureView: View {
    @Binding public var text: String
    public var onSubmit: (QuickCaptureParser.Result) -> Void
    public var onCancel: () -> Void

    public init(
        text: Binding<String>,
        onSubmit: @escaping (QuickCaptureParser.Result) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._text = text
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        let parsed = QuickCaptureParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            TextField("New task… (#tag, ^date)", text: $text)
                .textFieldStyle(.plain)
                .font(LillistTypography.quickCaptureField)
                .onSubmit { onSubmit(parsed) }
                .accessibilityLabel(String(localized: "Quick capture", bundle: .module))

            HStack(spacing: 6) {
                ForEach(parsed.tags, id: \.self) { name in
                    TagChipView(name: name)
                }
                if let token = parsed.dateToken {
                    Label(token, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("↩ save · esc cancel")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Date-token chips. Single source of truth shared with the
            // iOS QuickCaptureSheet via QuickCaptureDateSuggestions;
            // tapping appends `^token` to the text field for the inline
            // parser to pick up.
            HStack(spacing: 6) {
                ForEach(QuickCaptureDateSuggestions.default, id: \.self) { token in
                    Button {
                        text += text.isEmpty ? "^\(token)" : " ^\(token)"
                    } label: {
                        Text("^\(token)").font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Insert deadline \(token)", bundle: .module))
                }
                Spacer()
            }
        }
        .padding(LillistSpacing.m + 2)
        .frame(width: 520)
        // Plan 15 Task 17: switched from `.thickMaterial` to
        // `.regularMaterial` for a lighter Tahoe-native look.
        // `.glassBackgroundEffect()` is visionOS-only as of SDK 26.2;
        // when an analogous macOS modifier ships, wrap it in a
        // `#available`-guarded ViewModifier here.
        // Plan 17 Task 12: substitute an opaque fallback when the user
        // has enabled Reduce Transparency.
        #if os(macOS)
        .accessibleMaterial(
            .regularMaterial,
            fallback: Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: LillistRadius.m)
        )
        .onExitCommand(perform: onCancel)
        #else
        .accessibleMaterial(
            .regularMaterial,
            fallback: Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: LillistRadius.m)
        )
        #endif
    }
}
