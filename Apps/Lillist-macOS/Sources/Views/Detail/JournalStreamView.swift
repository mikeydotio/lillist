import SwiftUI
import LillistCore
import LillistUI

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

