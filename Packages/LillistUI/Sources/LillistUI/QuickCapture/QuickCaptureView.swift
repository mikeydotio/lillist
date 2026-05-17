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
                .accessibilityLabel("Quick capture")

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
        }
        .padding(LillistSpacing.m + 2)
        .frame(width: 520)
        // Plan 15 Task 17: switched from `.thickMaterial` to
        // `.regularMaterial` for a lighter Tahoe-native look.
        // `.glassBackgroundEffect()` is visionOS-only as of SDK 26.2;
        // when an analogous macOS modifier ships, wrap it in a
        // `#available`-guarded ViewModifier here.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: LillistRadius.m))
        #if os(macOS)
        .onExitCommand(perform: onCancel)
        #endif
    }
}
