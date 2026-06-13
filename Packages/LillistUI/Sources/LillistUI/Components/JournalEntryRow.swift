import SwiftUI
import LillistCore

/// Shared journal-entry row. Renders a `JournalStore.JournalRecord`
/// with a leading glyph derived from `entry.kind`, a timestamp, and
/// the entry body (Markdown-rendered).
///
/// Plan 14 lifted this from the macOS `JournalStreamView` (which had
/// the canonical glyph set) and the iOS `TaskJournalTab` (which had
/// no glyphs at all). Both apps now consume this view.
public struct JournalEntryRow: View {
    public var entry: JournalStore.JournalRecord

    public init(entry: JournalStore.JournalRecord) {
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.xs / 2) {
            HStack(spacing: LillistSpacing.xs) {
                Image(systemName: JournalGlyph.symbol(for: entry.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LillistColor.textFaint)
                Text(entry.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .font(LillistTypography.caption2)
                    .foregroundStyle(LillistColor.textFaint)
            }
            // i18n-exempt: user-authored journal entry body, not chrome.
            Text(LocalizedStringKey(entry.body))
                .font(LillistTypography.body)
                .foregroundStyle(LillistColor.textBody)
                .textSelection(.enabled)
        }
        .padding(.vertical, LillistSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// SF Symbol mapping for `JournalEntryKind`. Parallel to
/// `StatusGlyph` in shape — keeps glyph choices testable and replaces
/// the inline `switch` previously duplicated in two views.
public enum JournalGlyph {
    public static func symbol(for kind: JournalEntryKind) -> String {
        switch kind {
        case .note: return "text.bubble"
        case .statusChange: return "arrow.triangle.2.circlepath"
        case .attachment: return "paperclip"
        case .createdFollowUp: return "arrow.uturn.right.circle"
        }
    }
}
