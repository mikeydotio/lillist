#if os(iOS)
import SwiftUI

/// Live-parsed token chips for the iOS Quick Capture field.
///
/// Mirrors the macOS Quick Capture panel: as the user types, parsed
/// `#tag` chips and `^date` tokens render below the field so they
/// can confirm the parser saw what they meant before tapping Save.
/// `parsed.tags` become `TagChipView`s; a non-nil `parsed.dateToken`
/// renders as a calendar `Label`. Empty results collapse to zero
/// height — no row reserved for chips that aren't there.
struct QuickCaptureTokenChips: View {
    let parsed: QuickCaptureParser.Result

    var body: some View {
        if parsed.tags.isEmpty && parsed.dateToken == nil {
            EmptyView()
        } else {
            HStack(spacing: LillistSpacing.xs + 2) {
                ForEach(parsed.tags, id: \.self) { name in
                    TagChipView(name: name)
                }
                if let token = parsed.dateToken {
                    Label(token, systemImage: "calendar")
                        .font(LillistTypography.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(String(localized: "Parsed deadline \(token)", bundle: .module))
                }
            }
        }
    }
}
#endif
