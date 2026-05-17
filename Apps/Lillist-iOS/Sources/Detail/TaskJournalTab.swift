import SwiftUI
import LillistCore
import LillistUI

/// Journal tab: reverse-chronological note log plus a composer pinned
/// above the keyboard via `.safeAreaInset(edge: .bottom)`. The
/// `ScrollViewReader` scrolls the latest entry into view when the
/// composer takes focus so the user sees what they're replying to.
struct TaskJournalTab: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entries: [JournalStore.JournalRecord] = []
    @State private var composer: String = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List(entries, id: \.id) { entry in
                JournalEntryRow(entry: entry)
                    .id(entry.id)
            }
            .listStyle(.plain)
            .accessibilityLabel(String(localized: "Journal"))
            .safeAreaInset(edge: .bottom) {
                composer(proxy: proxy)
            }
            .task {
                await reload()
                if let last = entries.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func composer(proxy: ScrollViewProxy) -> some View {
        HStack {
            TextField("Add a journal entry…", text: $composer, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .focused($composerFocused)
                .onChange(of: composerFocused) { _, isFocused in
                    guard isFocused, let last = entries.last?.id else { return }
                    if reduceMotion {
                        proxy.scrollTo(last, anchor: .bottom)
                    } else {
                        withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            Button("Post") { Task { await post() } }
                .disabled(composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.thinMaterial)
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
