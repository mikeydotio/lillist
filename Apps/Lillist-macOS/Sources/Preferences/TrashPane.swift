import SwiftUI
import LillistCore

/// macOS Preferences Trash pane.
///
/// Slider controls the auto-purge retention window (7-365 days).
/// "Empty Trash now" calls `TaskStore.purgeAll()` after confirmation.
struct TrashPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var isEmptying = false
    @State private var emptyResult: String?
    @State private var confirmingEmpty = false

    var body: some View {
        Form {
            if let b = binding {
                Section("Retention") {
                    Slider(
                        value: Binding(
                            get: { Double(b.wrappedValue.trashRetentionDays) },
                            set: { b.wrappedValue.trashRetentionDays = Int16($0.rounded()) }
                        ),
                        in: 7...365,
                        step: 1
                    ) {
                        Text("Days in Trash before auto-purge")
                    }
                    Text("\(b.wrappedValue.trashRetentionDays) days")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(role: .destructive) {
                        confirmingEmpty = true
                    } label: {
                        if isEmptying {
                            ProgressView().controlSize(.small)
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
                        Text("Tasks in Trash will be permanently deleted and cannot be recovered.")
                    }
                    if let emptyResult {
                        Text(emptyResult)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .fixedSize() // Plan 15 Task 26: pane self-sizes; window animates
        .task { prefs = try? await environment.preferencesStore.read() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func emptyTrash() async {
        isEmptying = true
        defer { isEmptying = false }
        do {
            let purged = try await environment.taskStore.purgeAll()
            emptyResult = purged == 0
                ? "Trash was already empty."
                : "Emptied \(purged) task\(purged == 1 ? "" : "s") from Trash."
        } catch {
            emptyResult = "Couldn't empty Trash: \(error.localizedDescription)"
        }
    }
}
