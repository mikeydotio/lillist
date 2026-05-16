import SwiftUI
import LillistCore

struct TrashSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var emptyResult: String?
    @State private var isEmptying = false
    @State private var confirmingEmpty = false

    var body: some View {
        Section("Trash") {
            VStack(alignment: .leading) {
                Slider(
                    value: Binding(
                        get: { Double(prefs.trashRetentionDays) },
                        set: { prefs.trashRetentionDays = Int16($0.rounded()) }
                    ),
                    in: 7...365,
                    step: 1
                )
                Text("Retain trashed tasks for \(prefs.trashRetentionDays) days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                confirmingEmpty = true
            } label: {
                if isEmptying {
                    ProgressView()
                } else {
                    Text("Empty Trash now")
                }
            }
            .disabled(isEmptying)
            .confirmationDialog(
                "Empty Trash?",
                isPresented: $confirmingEmpty,
                titleVisibility: .visible
            ) {
                Button("Empty Trash", role: .destructive) {
                    Task { await emptyTrash() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Tasks in Trash will be permanently deleted.")
            }
            if let emptyResult {
                Text(emptyResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let purged = try await environment.taskStore.purgeAll()
            emptyResult = purged == 0
                ? "Trash was already empty."
                : "Emptied \(purged) task\(purged == 1 ? "" : "s")."
        } catch {
            emptyResult = "Couldn't empty Trash: \(error.localizedDescription)"
        }
    }
}
