import SwiftUI
import LillistCore
import LillistUI

struct TrashSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var emptyResult: String?
    @State private var isEmptying = false
    @State private var confirmingEmpty = false

    private static let presets: [Int16] = [7, 14, 30, 60, 90, 180, 365]

    init(prefs: Binding<PreferencesStore.Prefs>) {
        self._prefs = prefs
        // Coerce a pre-Plan-26 custom value (e.g. 45 from the old slider)
        // into the nearest preset so `Picker` can render it cleanly.
        let current = prefs.wrappedValue.trashRetentionDays
        if !Self.presets.contains(current) {
            let nearest = Self.presets.min(by: { abs($0 - current) < abs($1 - current) }) ?? 30
            prefs.wrappedValue.trashRetentionDays = nearest
        }
    }

    var body: some View {
        Section("Trash") {
            Picker("Retain trashed tasks for", selection: Binding(
                get: { Int(prefs.trashRetentionDays) },
                set: { prefs.trashRetentionDays = Int16($0) }
            )) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("1 year").tag(365)
            }
            .pickerStyle(.menu)
            .accessibilityValue(String(localized: "\(prefs.trashRetentionDays) days"))

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
            let result = purged == 0
                ? String(localized: "Trash was already empty.")
                : String(localized: "Emptied \(purged) task\(purged == 1 ? "" : "s").")
            emptyResult = result
            AccessibilityAnnouncements.post(result, priority: .low)
        } catch {
            let failure = String(localized: "Couldn't empty Trash: \(error.localizedDescription)")
            emptyResult = failure
            AccessibilityAnnouncements.post(failure, priority: .high)
        }
    }
}
