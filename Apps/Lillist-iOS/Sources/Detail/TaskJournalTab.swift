import SwiftUI
import LillistCore

/// Journal tab: reverse-chronological note log plus a composer at the
/// bottom. Backed by `JournalStore.entries(forTask:)` and `appendNote`.
struct TaskJournalTab: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env

    @State private var entries: [JournalStore.JournalRecord] = []
    @State private var composer: String = ""

    var body: some View {
        VStack(spacing: 0) {
            List(entries, id: \.id) { entry in
                JournalEntryRow(entry: entry)
            }
            .listStyle(.plain)
            Divider()
            HStack {
                TextField("Add a journal entry…", text: $composer, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                Button("Post") { Task { await post() } }
                    .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .task { await reload() }
        .accessibilityLabel("Journal")
    }

    private func reload() async {
        entries = (try? await env.journalStore.entries(forTask: taskID)) ?? []
    }

    private func post() async {
        let trimmed = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? await env.journalStore.appendNote(taskID: taskID, body: trimmed)
        composer = ""
        await reload()
    }
}

private struct JournalEntryRow: View {
    let entry: JournalStore.JournalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.body)
                .lineLimit(nil)
            if let createdAt = entry.createdAt {
                Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
