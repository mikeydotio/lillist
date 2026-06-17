import SwiftUI
import LillistCore

/// Subtask list + inline add, for the unified editor's full mode.
/// Display-only rows (status cube + title); tapping a row asks the host to
/// re-target the singleton editor to the child.
struct EditorSubtasksSection: View {
    var subtasks: [TaskStore.TaskRecord]
    var onAdd: (String) -> Void
    var onOpen: ((UUID) -> Void)?

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            ForEach(subtasks, id: \.id) { child in
                Button {
                    onOpen?(child.id)
                } label: {
                    HStack(spacing: LillistSpacing.s) {
                        StatusCubeView(status: child.status)
                            .frame(width: 18, height: 18)
                        Text(child.title)
                            .font(LillistTypography.body)
                            .foregroundStyle(LillistColor.textBody)
                            .strikethrough(child.status == .closed)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onOpen == nil)
            }

            HStack(spacing: LillistSpacing.s) {
                TextField(
                    text: $draft,
                    prompt: Text("Add a subtask", bundle: .module)
                ) {
                    Text("Add a subtask", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(LillistTypography.body)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("AddSubtaskField")

                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(RainbowPalette.scriptPurple.base)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "Add subtask", bundle: .module))
            }
            .padding(.horizontal, LillistSpacing.m)
            .padding(.vertical, LillistSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .fill(.rainbowWell)
            }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        draft = ""
    }
}

/// Journal stream (read-only entries) + a note composer.
struct EditorJournalSection: View {
    var entries: [JournalStore.JournalRecord]
    var onAddNote: (String) -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LillistSpacing.s) {
            ForEach(entries, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.body)
                        .font(LillistTypography.subheadline)
                        .foregroundStyle(LillistColor.textBody)
                    if let at = entry.createdAt {
                        Text(at, style: .relative)
                            .font(LillistTypography.caption2)
                            .foregroundStyle(LillistColor.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: LillistSpacing.s) {
                TextField(
                    text: $draft,
                    prompt: Text("Add a note", bundle: .module)
                ) {
                    Text("Add a note", bundle: .module)
                }
                .textFieldStyle(.plain)
                .font(LillistTypography.body)
                .submitLabel(.done)
                .onSubmit(commit)
                .accessibilityIdentifier("AddJournalNoteField")

                Button(action: commit) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(RainbowPalette.scriptPurple.base)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(String(localized: "Add note", bundle: .module))
            }
            .padding(.horizontal, LillistSpacing.m)
            .padding(.vertical, LillistSpacing.s)
            .background {
                RoundedRectangle(cornerRadius: LillistRadius.s, style: .continuous)
                    .fill(.rainbowWell)
            }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onAddNote(trimmed)
        draft = ""
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
