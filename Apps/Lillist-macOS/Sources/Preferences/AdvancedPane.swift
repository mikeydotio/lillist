import SwiftUI
import LillistUI
import AppKit
import LillistCore

/// macOS Preferences Advanced pane (Plan 10 Task 9).
///
/// Two actions:
/// - **Export now…**: triggers `LillistCore.Exporter.export(to:)` against a
///   user-chosen directory (NSOpenPanel), reveals the result in Finder on
///   success.
/// - **Reveal store in Finder**: opens the SQLite file location via
///   `NSWorkspace.activateFileViewerSelecting`.
struct AdvancedPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var lastExportError: String?
    @State private var importSummary: Importer.ImportSummary?
    @State private var confirmingReset: ResetKind?
    @State private var isResetting = false
    @State private var resetResult: String?
    @State private var resetResultIsError = false

    /// Which reset the user is confirming. A single field (rather than
    /// independent booleans) so the destructive confirmations can't both
    /// present at once. Mirrors iOS `ResetDataStoreSection` — see its doc
    /// for why these three paths exist, when each is appropriate, and how
    /// the two propagating ones actually reach other devices (issue #71).
    /// Issue #66 found macOS had no self-serve equivalent of this iOS
    /// tool, so a stuck device there had no in-app recovery path.
    private enum ResetKind: Identifiable {
        case redownload
        case eraseEverywhere
        case reseedFromThisDevice
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section("Data") {
                Button {
                    Task { await runExport() }
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Export now…")
                    }
                }
                .disabled(isExporting)

                Button {
                    Task { await runImport() }
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import Data…")
                    }
                }
                .disabled(isImporting)

                if let summary = importSummary {
                    Text("Imported \(summary.tasksInserted) tasks, updated \(summary.tasksUpdated), skipped \(summary.tasksSkipped).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button("Reveal store in Finder") {
                    revealStoreInFinder()
                }
            }
            if let lastExportError {
                Section {
                    Text(lastExportError)
                        .font(.callout)
                        .foregroundStyle(RainbowPalette.cautionAmber.ink)
                }
            }
            resetSection
        }
        .formStyle(.grouped)
        .confirmationDialog(
            resetConfirmTitle,
            isPresented: resetConfirmBinding,
            titleVisibility: .visible,
            presenting: confirmingReset
        ) { kind in
            Button(resetConfirmButtonLabel(kind), role: .destructive) {
                Task { await runReset(kind) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { kind in
            Text(resetConfirmMessage(kind))
        }
    }

    // MARK: - Reset (issue #66: macOS parity with iOS's ResetDataStoreSection)

    @ViewBuilder
    private var resetSection: some View {
        Section {
            // Recommended-first: re-download keeps the iCloud copy and only
            // appears while syncing (nothing to download in local-only mode).
            if environment.currentSyncMode == .iCloudSync {
                resetButton(.redownload, title: "Erase Local Data and Download Fresh…")
            }
            resetButton(.eraseEverywhere, title: "Erase Data from All Devices and Start Over…")
            resetButton(.reseedFromThisDevice, title: "Erase Data from All Devices and Restore All from This Device's Backup…")

            if let resetResult {
                Text(resetResult)
                    .font(.callout)
                    .foregroundStyle(resetResultIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
            }
        } header: {
            Text("Reset")
        } footer: {
            Text("Use when you suspect the local data store is corrupted, or to deliberately reset every device on this account. Erase Local Data keeps your iCloud data and re-downloads it. The other two options also tell every other signed-in device to erase and converge — to empty, or to this device's data — the next time each is open and online. A local backup is kept for 30 days. Relaunch Lillist after resetting.")
        }
    }

    @ViewBuilder
    private func resetButton(_ kind: ResetKind, title: LocalizedStringKey) -> some View {
        Button(role: .destructive) {
            confirmingReset = kind
        } label: {
            if isResetting, confirmingReset == kind {
                ProgressView().controlSize(.small)
            } else {
                Text(title)
            }
        }
        .disabled(isResetting)
    }

    private var resetConfirmBinding: Binding<Bool> {
        Binding(get: { confirmingReset != nil }, set: { if !$0 { confirmingReset = nil } })
    }

    private var resetConfirmTitle: String {
        switch confirmingReset {
        case .redownload: return String(localized: "Erase Local Data?")
        case .eraseEverywhere: return String(localized: "Erase Everywhere?")
        case .reseedFromThisDevice: return String(localized: "Restore Everywhere from This Device?")
        case nil: return ""
        }
    }

    private func resetConfirmButtonLabel(_ kind: ResetKind) -> LocalizedStringKey {
        switch kind {
        case .redownload: return "Erase & Download"
        case .eraseEverywhere: return "Erase Everywhere"
        case .reseedFromThisDevice: return "Restore from This Device"
        }
    }

    private func resetConfirmMessage(_ kind: ResetKind) -> String {
        switch kind {
        case .redownload:
            return String(localized: "This deletes the copy on this device and downloads a fresh copy of everything from iCloud. Other devices are unaffected. A local backup is kept for 30 days.")
        case .eraseEverywhere:
            return String(localized: "This permanently deletes every task on this device and in iCloud. Other devices signed in to this account will also erase their data and start fresh the next time they're open and connected to the internet. A local backup of this device is kept for 30 days. This cannot be undone.")
        case .reseedFromThisDevice:
            return String(localized: "This device's current data becomes the new copy everywhere: iCloud and every other device signed in to this account will erase their existing data and adopt this device's data the next time they're open and connected to the internet. A backup of the previous state on each device is kept locally for 30 days. This cannot be undone.")
        }
    }

    private func runReset(_ kind: ResetKind) async {
        isResetting = true
        resetResult = nil
        resetResultIsError = false
        defer { isResetting = false }
        do {
            switch kind {
            case .redownload:
                try await environment.dataStoreReset.resetAndRedownload()
                let msg = String(localized: "Local data cleared — downloading from iCloud. Relaunch Lillist once sync settles.")
                resetResult = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            case .eraseEverywhere:
                try await environment.dataStoreReset.resetEverywhereToEmpty()
                let msg = String(localized: "Data store reset. Your other devices will erase and reload the next time they're open and online. Relaunch Lillist to reload.")
                resetResult = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            case .reseedFromThisDevice:
                try await environment.dataStoreReset.resetAndReseedFromThisDevice()
                let msg = String(localized: "This device is now the source of truth. Your other devices will catch up the next time they're open and online. Relaunch Lillist to reload.")
                resetResult = msg
                AccessibilityAnnouncements.post(msg, priority: .high)
            }
        } catch {
            let failure = String(localized: "Reset failed: \(error.localizedDescription)")
            resetResult = failure
            resetResultIsError = true
            AccessibilityAnnouncements.post(failure, priority: .high)
        }
    }

    private func runExport() async {
        // Pick a *fresh* empty directory inside a user-chosen parent —
        // Exporter requires its destination to be empty, and forcing the
        // user to create a directory first is hostile.
        let panel = NSOpenPanel()
        panel.title = "Choose an export destination"
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let parent = panel.url else { return }

        let ts = Int(Date().timeIntervalSince1970)
        let dir = parent.appendingPathComponent("Lillist-Export-\(ts)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        } catch {
            lastExportError = "Couldn't create export directory: \(error.localizedDescription)"
            return
        }

        isExporting = true
        defer { isExporting = false }
        do {
            let exporter = Exporter(
                persistence: environment.persistence,
                preferences: environment.preferencesStore
            )
            try await exporter.export(to: dir)
            lastExportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            lastExportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func runImport() async {
        let panel = NSOpenPanel()
        panel.title = "Choose a Lillist export folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImporting = true
        defer { isImporting = false }
        let importer = Importer(persistence: environment.persistence)
        do {
            importSummary = try await importer.importBundle(at: url, conflictPolicy: .skipExisting)
            lastExportError = nil
        } catch {
            lastExportError = "Import failed: \(error.localizedDescription)"
        }
    }

    private func revealStoreInFinder() {
        guard case .onDisk(let url) = environment.persistence.configuration.storeKind else {
            lastExportError = "In-memory store has no file to reveal."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
