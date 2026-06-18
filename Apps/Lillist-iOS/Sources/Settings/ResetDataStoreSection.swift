import SwiftUI
import LillistCore
import LillistUI

/// Settings → Debug → Reset. A destructive, irreversible full data-store
/// reset for when the local Core Data store is suspected corrupt: it
/// backs up, erases the CloudKit zone (when syncing), destroys the local
/// store, and rebuilds it empty. Because the wipe propagates to every
/// device on the account, the action is gated behind an explicit
/// confirmation with unambiguous copy.
struct ResetDataStoreSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirming = false
    @State private var isResetting = false
    @State private var result: String?
    @State private var resultIsError = false

    var body: some View {
        Section {
            Button(role: .destructive) {
                confirming = true
            } label: {
                if isResetting {
                    ProgressView()
                } else {
                    Text("Reset data store…")
                }
            }
            .disabled(isResetting)
            .confirmationDialog(
                "Reset data store?",
                isPresented: $confirming,
                titleVisibility: .visible
            ) {
                Button("Erase Everything", role: .destructive) {
                    Task { await runReset() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every task on this device and in iCloud — on all devices signed in to this account. A local backup is kept for 30 days. This cannot be undone.")
            }
            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(resultIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("Reset")
        } footer: {
            Text("Use when you suspect the local data store is corrupted. After resetting, relaunch Lillist to reload.")
        }
    }

    private func runReset() async {
        isResetting = true
        result = nil
        resultIsError = false
        defer { isResetting = false }
        do {
            try await environment.dataStoreReset.resetAllData()
            let msg = String(localized: "Data store reset. Relaunch Lillist to reload.")
            result = msg
            AccessibilityAnnouncements.post(msg, priority: .high)
        } catch {
            let failure = String(localized: "Reset failed: \(error.localizedDescription)")
            result = failure
            resultIsError = true
            AccessibilityAnnouncements.post(failure, priority: .high)
        }
    }
}
