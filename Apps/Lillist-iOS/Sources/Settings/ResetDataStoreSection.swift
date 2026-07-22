import SwiftUI
import LillistCore
import LillistUI

/// Settings → Debug → Reset. Destructive, irreversible recovery for when
/// the local Core Data store is suspected corrupt, or to deliberately
/// re-converge every device on this iCloud account. Three paths, each
/// gated behind an explicit confirmation with unambiguous copy:
///
/// - **Erase local data and download fresh** (iCloud Sync only) — deletes
///   this device's local copy and re-downloads everything from iCloud.
///   Other devices are untouched; this is the recommended fix for a
///   corrupt *local* store.
/// - **Erase data from all devices and start over** — erases every task
///   on this device and in iCloud, then rebuilds empty. Every other
///   device signed in to this account converges on empty the next time
///   it's open and online (issue #71 — see below for how).
/// - **Erase data from all devices and restore all from this device's
///   backup** — this device's *current* data becomes the account's new
///   truth. Every other device discards its own data and adopts this
///   device's instead, the next time it's open and online.
///
/// ## How "all devices" actually converges (issue #71)
///
/// The previous two-button version of this screen erased the CloudKit
/// zone and assumed that alone would make other devices notice and wipe
/// themselves — it does not. `NSPersistentCloudKitContainer` has no
/// receiving-side reaction to a deleted zone; a peer's local store and
/// import-history metadata are untouched, so it simply re-creates the
/// zone and re-uploads its own data, resurrecting everything. The two
/// propagating actions below now also broadcast an explicit signal over
/// `ResetSignalMonitor`/`ControlInbox` — a small, out-of-band iCloud
/// Key-Value Store channel, independent of the Core Data/CloudKit mirror
/// so it survives the kind of wedged export queue issue #66 diagnosed.
/// Delivery isn't instant or backgrounded, hence "the next time it's
/// open and online" in the copy below, not "immediately."
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
        case eraseEverywhere
        case reseedFromThisDevice
        var id: Self { self }
    }

    var body: some View {
        Section {
            // Recommended-first: re-download keeps the iCloud copy and only
            // appears while syncing (nothing to download in local-only mode).
            if environment.currentSyncMode == .iCloudSync {
                resetButton(.redownload, title: "Erase Local Data and Download Fresh…")
            }
            resetButton(.eraseEverywhere, title: "Erase Data from All Devices and Start Over…")
            resetButton(.reseedFromThisDevice, title: "Erase Data from All Devices and Restore All from This Device's Backup…")

            if let result {
                Text(result)
                    .font(.footnote)
                    .foregroundStyle(resultIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("Reset")
        } footer: {
            Text("Use when you suspect the local data store is corrupted, or to deliberately reset every device on this account. Erase Local Data keeps your iCloud data and re-downloads it. The other two options also tell every other signed-in device to erase and converge — to empty, or to this device's data — the next time each is open and online. A local backup is kept for 30 days. Relaunch Lillist after resetting.")
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
        case .redownload: return String(localized: "Erase Local Data?")
        case .eraseEverywhere: return String(localized: "Erase Everywhere?")
        case .reseedFromThisDevice: return String(localized: "Restore Everywhere from This Device?")
        case nil: return ""
        }
    }

    private func confirmButtonLabel(_ kind: ResetKind) -> LocalizedStringKey {
        switch kind {
        case .redownload: return "Erase & Download"
        case .eraseEverywhere: return "Erase Everywhere"
        case .reseedFromThisDevice: return "Restore from This Device"
        }
    }

    private func confirmMessage(_ kind: ResetKind) -> String {
        switch kind {
        case .redownload:
            return String(localized: "This deletes the copy on this device and downloads a fresh copy of everything from iCloud. Other devices are unaffected. A local backup is kept for 30 days.")
        case .eraseEverywhere:
            return String(localized: "This permanently deletes every task on this device and in iCloud. Other devices signed in to this account will also erase their data and start fresh the next time they're open and connected to the internet. A local backup of this device is kept for 30 days. This cannot be undone.")
        case .reseedFromThisDevice:
            return String(localized: "This device's current data becomes the new copy everywhere: iCloud and every other device signed in to this account will erase their existing data and adopt this device's data the next time they're open and connected to the internet. A backup of the previous state on each device is kept locally for 30 days. This cannot be undone.")
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
            case .eraseEverywhere:
                try await environment.dataStoreReset.resetEverywhereToEmpty()
                let msg = String(localized: "Data store reset. Your other devices will erase and reload the next time they're open and online. Relaunch Lillist to reload.")
                result = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            case .reseedFromThisDevice:
                try await environment.dataStoreReset.resetAndReseedFromThisDevice()
                let msg = String(localized: "This device is now the source of truth. Your other devices will catch up the next time they're open and online. Relaunch Lillist to reload.")
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
