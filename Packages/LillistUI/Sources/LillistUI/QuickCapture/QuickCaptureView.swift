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
            TextField(
                text: $text,
                prompt: Text("Capture a task…  #tag ^date", bundle: .module)
            ) {
                Text("New task", bundle: .module)
            }
            .textFieldStyle(.plain)
            .font(LillistTypography.quickCaptureField)
            .foregroundStyle(LillistColor.textStrong)
            .onSubmit { onSubmit(parsed) }
            .accessibilityLabel(String(localized: "Quick capture", bundle: .module))
            .padding(.horizontal, LillistSpacing.s + 2)
            .padding(.vertical, LillistSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .fill(.rainbowWell)
            }
            .overlay {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .strokeBorder(LillistColor.borderHair, lineWidth: 1)
            }

            HStack(spacing: 6) {
                ForEach(parsed.tags, id: \.self) { name in
                    TagChipView(name: name, style: .meta)
                }
                if let token = parsed.dateToken {
                    Label(token, systemImage: "clock")
                        .font(LillistTypography.caption)
                        .foregroundStyle(LillistColor.textMuted)
                }
                Spacer()
                Text("↩ save · esc cancel")
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textFaint)
            }

            // Date-token chips. Sourced from QuickCaptureDateSuggestions
            // — historically shared with the iOS sheet's chip row, but
            // the iOS dialog redesign (Plan 22) dropped the row. Tapping
            // appends `^token` to the text field for the inline parser
            // to pick up.
            HStack(spacing: 6) {
                ForEach(QuickCaptureDateSuggestions.default, id: \.self) { token in
                    Button {
                        text += text.isEmpty ? "^\(token)" : " ^\(token)"
                    } label: {
                        Text("^\(token)")
                    }
                    .buttonStyle(.rainbow(.secondary, size: .sm))
                    .accessibilityLabel(String(localized: "Insert deadline \(token)", bundle: .module))
                }
                Spacer()
            }
        }
        .padding(LillistSpacing.m + 2)
        .frame(width: 520)
        // Rainbow Glass: the quick-capture panel is a floating
        // control-layer surface, so it gets Liquid Glass on OS 26 and
        // degrades to `.regularMaterial` → opaque fallback below it (the
        // `#available` + Reduce-Transparency ladder lives in
        // `GlassSurface`). Supersedes the earlier `.regularMaterial`
        // treatment that was waiting for a macOS glass modifier to ship.
        // NB: the macOS NSPanel host must stay non-opaque for glass to
        // show through (handled by `QuickCapturePanelController`).
        .glassSurface(.panel, in: RoundedRectangle(cornerRadius: LillistRadius.m))
        #if os(macOS)
        .onExitCommand(perform: onCancel)
        #endif
    }
}
