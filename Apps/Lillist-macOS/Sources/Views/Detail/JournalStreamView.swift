import SwiftUI
import LillistCore
import LillistUI

struct JournalStreamView: View {
    enum Filter: Hashable { case all, attachments }

    @Environment(AppEnvironment.self) private var env
    let taskID: UUID
    @State private var entries: [JournalStore.JournalRecord] = []
    @State private var filter: Filter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Journal & Attachments").font(.headline)
                Spacer()
                Picker("Filter", selection: $filter) {
                    Text("All").tag(Filter.all)
                    Text("Attachments").tag(Filter.attachments)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
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
        switch filter {
        case .all:         return entries
        case .attachments: return entries.filter { $0.kind == .attachment }
        }
    }

    private func refresh() async {
        entries = (try? await env.journalStore.entries(forTask: taskID)) ?? []
    }
}

