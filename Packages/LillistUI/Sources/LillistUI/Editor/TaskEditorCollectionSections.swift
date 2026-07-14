import SwiftUI
import LillistCore

/// Journal stream (read-only entries). Each entry shows its absolute
/// timestamp inline with the change text to stay compact — no auto-updating
/// relative labels, and no note composer (manual notes were retired).
struct EditorJournalSection: View {
    var entries: [JournalStore.JournalRecord]

    /// Fixed `yyyy-MM-dd HH:mm:ss` stamp. POSIX locale so the numeric format
    /// is stable regardless of the user's locale; current time zone so the
    /// time reads as wall-clock-local to the user.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            if entries.isEmpty {
                Text("No activity yet.", bundle: .module)
                    .font(LillistTypography.caption)
                    .foregroundStyle(LillistColor.textFaint)
            }
            ForEach(entries, id: \.id) { entry in
                HStack(alignment: .firstTextBaseline, spacing: LillistSpacing.xs + 2) {
                    if let at = entry.createdAt {
                        Text(Self.timestampFormatter.string(from: at))
                            .font(LillistTypography.caption2)
                            .monospaced()
                            .foregroundStyle(LillistColor.textFaint)
                            .layoutPriority(1)
                    }
                    Text(entry.body)
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(LillistColor.textBody)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Attachment list + delete. Acquisition (`PhotosPicker` / `NSOpenPanel`) is
/// platform-specific, so the "add" affordance is an injected host action.
struct EditorAttachmentsSection: View {
    var attachments: [AttachmentStore.AttachmentRecord]
    var onAddTapped: (() -> Void)?
    var onDelete: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            ForEach(attachments, id: \.id) { att in
                HStack(spacing: LillistSpacing.s) {
                    Image(systemName: Self.symbol(for: att.kind))
                        .foregroundStyle(RainbowPalette.focusBlue.base)
                    Text(att.filename)
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(LillistColor.textBody)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Button {
                        onDelete(att.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(LillistColor.textFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Delete attachment", bundle: .module))
                }
            }

            if let onAddTapped {
                Button(action: onAddTapped) {
                    Label {
                        Text("Add attachment", bundle: .module)
                    } icon: {
                        Image(systemName: "paperclip")
                    }
                }
                .buttonStyle(.rainbow(.lavender, size: .sm))
                .accessibilityIdentifier("AddAttachmentButton")
            }
        }
    }

    private static func symbol(for kind: AttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .file: return "doc"
        case .linkPreview: return "link"
        }
    }
}
