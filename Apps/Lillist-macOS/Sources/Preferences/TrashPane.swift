import SwiftUI
import LillistCore

/// macOS Preferences Trash pane (Plan 10 Task 9).
///
/// Slider controls the auto-purge retention window (7-365 days).
/// "Empty Trash now" — Plan 10 leaves this as a stub button: the
/// canonical purge job lives in LillistCore.AutoPurgeJob (Plan 1
/// follow-up), which doesn't have an "empty now" public method on
/// `main`. The button surfaces the affordance but logs a TODO until a
/// `forceAll`-style API lands.
struct TrashPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var isEmptying = false
    @State private var emptyResult: String?

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
                        Task { await emptyTrash() }
                    } label: {
                        if isEmptying {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Empty Trash now")
                        }
                    }
                    .disabled(isEmptying)
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
        // TODO(Plan 1 follow-up): wire a public `purgeAll()` method on
        // AutoPurgeJob (or TaskStore.permanentlyDeleteAll(filter:.trashed)).
        // For now this is a no-op affordance — surface a friendly
        // explanation so the button isn't silently broken.
        emptyResult = "Empty-now isn't wired up yet. Trashed tasks will purge automatically after \(prefs?.trashRetentionDays ?? 30) days."
    }
}
