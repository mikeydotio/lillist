import SwiftUI
import LillistCore
import LillistUI

/// Settings → Debug → Reset. Destructive, irreversible recovery for when
/// the local Core Data store is suspected corrupt. Two paths, each gated
/// behind an explicit confirmation with unambiguous copy:
///
/// - **Reset & Download Data** (iCloud Sync only) — deletes this device's
///   local copy and re-downloads everything from iCloud. The iCloud copy
///   and other devices are untouched; this is the recommended fix for a
///   corrupt *local* store.
/// - **Reset Everywhere** — erases every task on this device and in iCloud,
///   on all devices on the account, then rebuilds empty. The nuclear option.
struct ResetDataStoreSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirming: ResetKind?
    @State private var isResetting = false
    @State private var result: String?
    @State private var resultIsError = false

    /// Which reset the user is confirming. Drives a single
    /// `confirmationDialog` so two destructive paths can't both present at
    /// once (the multiple-presentation pitfall this codebase guards against).
    private enum ResetKind: Identifiable {
        case redownload
        case everywhere
        var id: Self { self }
    }

    var body: some View {
        Section {
            // Recommended-first: re-download keeps the iCloud copy and only
            // appears while syncing (nothing to download in local-only mode).
            if environment.currentSyncMode == .iCloudSync {
                resetButton(.redownload, title: "Reset & Download Data…")
            }
            resetButton(.everywhere, title: "Reset Everywhere…")

            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(resultIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("Reset")
        } footer: {
            Text("Use when you suspect the local data store is corrupted. Reset & Download keeps your iCloud data and re-downloads it; Reset Everywhere erases every task on all devices. A local backup is kept for 30 days. Relaunch Lillist after resetting.")
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: confirmBinding,
            titleVisibility: .visible,
            presenting: confirming
        ) { kind in
            Button(confirmButtonLabel(kind), role: .destructive) {
                Task { await runReset(kind) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(confirmMessage(kind))
        }
    }

    @ViewBuilder
    private func resetButton(_ kind: ResetKind, title: LocalizedStringKey) -> some View {
        Button(role: .destructive) {
            confirming = kind
        } label: {
            if isResetting, confirming == kind {
                ProgressView()
            } else {
                Text(title)
            }
        }
        .disabled(isResetting)
    }

    // MARK: - Confirmation copy

    private var confirmBinding: Binding<Bool> {
        Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
    }

    private var confirmTitle: String {
        switch confirming {
        case .redownload: return String(localized: "Reset & Download Data?")
        case .everywhere: return String(localized: "Reset Everywhere?")
        case nil: return ""
        }
    }

    private func confirmButtonLabel(_ kind: ResetKind) -> LocalizedStringKey {
        switch kind {
        case .redownload: return "Reset & Download"
        case .everywhere: return "Erase Everywhere"
        }
    }

    private func confirmMessage(_ kind: ResetKind) -> String {
        switch kind {
        case .redownload:
            return String(localized: "This deletes the copy on this device and downloads a fresh copy of everything from iCloud. Your iCloud data and other devices are unaffected. A local backup is kept for 30 days.")
        case .everywhere:
            return String(localized: "This permanently deletes every task on this device and in iCloud — on all devices signed in to this account. A local backup is kept for 30 days. This cannot be undone.")
        }
    }

    // MARK: - Execution

    private func runReset(_ kind: ResetKind) async {
        isResetting = true
        result = nil
        resultIsError = false
        defer { isResetting = false }
        do {
            switch kind {
            case .redownload:
                try await environment.dataStoreReset.resetAndRedownload()
                let msg = String(localized: "Local data cleared — downloading from iCloud. Relaunch Lillist once sync settles.")
                result = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            case .everywhere:
                try await environment.dataStoreReset.resetAllData()
                let msg = String(localized: "Data store reset. Relaunch Lillist to reload.")
                result = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            }
        } catch {
            let failure = String(localized: "Reset failed: \(error.localizedDescription)")
            result = failure
            resultIsError = true
            AccessibilityAnnouncements.post(failure, priority: .high)
        }
    }
}
