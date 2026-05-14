import SwiftUI
import LillistCore

struct TrashSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var emptyResult: String?

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
            // TODO(Plan 1 follow-up): wire a public purgeAll() on
            // AutoPurgeJob so this button has a real implementation.
            Button(role: .destructive) {
                emptyResult = "Empty-now isn't wired up yet. Trashed tasks will purge automatically after \(prefs.trashRetentionDays) days."
            } label: {
                Text("Empty Trash now")
            }
            if let emptyResult {
                Text(emptyResult)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
