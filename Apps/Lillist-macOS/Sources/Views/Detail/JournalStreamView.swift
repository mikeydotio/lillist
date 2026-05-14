import SwiftUI
import LillistCore

struct JournalStreamView: View {
    @Environment(AppEnvironment.self) private var env
    let taskID: UUID
    @State private var entries: [JournalStore.JournalRecord] = []
    @State private var filterAttachmentsOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Journal & Attachments").font(.headline)
                Spacer()
                Toggle("Attachments only", isOn: $filterAttachmentsOnly)
                    .toggleStyle(.switch).controlSize(.mini)
            }
            if entries.isEmpty {
                Text("No entries yet.").foregroundStyle(.secondary).font(.subheadline)
            } else {
                ForEach(filtered, id: \.id) { entry in
                    JournalEntryRow(entry: entry)
                }
            }
            JournalComposerView(taskID: taskID) {
                Task { await refresh() }
            }
        }
        .padding()
        .task { await refresh() }
        .onChange(of: taskID) { _, _ in Task { await refresh() } }
    }

    private var filtered: [JournalStore.JournalRecord] {
        filterAttachmentsOnly ? entries.filter { $0.kind == .attachment } : entries
    }

    private func refresh() async {
        entries = (try? await env.journalStore.entries(forTask: taskID)) ?? []
    }
}

private struct JournalEntryRow: View {
    let entry: JournalStore.JournalRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                Text(entry.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(LocalizedStringKey(entry.body))
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
    private var icon: String {
        switch entry.kind {
        case .note: return "text.bubble"
        case .statusChange: return "arrow.triangle.2.circlepath"
        case .attachment: return "paperclip"
        case .createdFollowUp: return "arrow.uturn.right.circle"
        }
    }
}
