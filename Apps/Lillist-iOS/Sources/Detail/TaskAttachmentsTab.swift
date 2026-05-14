import SwiftUI
import LillistCore

/// Attachments tab: grid of attachments associated with the task. Tap to
/// download via `AttachmentStore.downloadData(id:)` (lands the bytes from
/// CloudKit if not already cached).
struct TaskAttachmentsTab: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var items: [AttachmentStore.AttachmentRecord] = []

    var body: some View {
        ScrollView {
            if items.isEmpty {
                ContentUnavailableView(
                    "No attachments",
                    systemImage: "paperclip",
                    description: Text("Use the Share sheet to add an image, file, or link to this task.")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                    ForEach(items, id: \.id) { att in
                        AttachmentTile(attachment: att)
                    }
                }
                .padding()
            }
        }
        .task { await reload() }
        .accessibilityLabel("Attachments")
    }

    private func reload() async {
        items = (try? await env.attachmentStore.attachments(forTask: taskID)) ?? []
    }
}

private struct AttachmentTile: View {
    let attachment: AttachmentStore.AttachmentRecord

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 32))
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kindLabel) — \(attachment.filename)")
    }

    private var glyph: String {
        switch attachment.kind {
        case .image: return "photo"
        case .file: return "doc"
        case .linkPreview: return "link"
        }
    }

    private var kindLabel: String {
        switch attachment.kind {
        case .image: return "Image"
        case .file: return "File"
        case .linkPreview: return "Link"
        }
    }
}
