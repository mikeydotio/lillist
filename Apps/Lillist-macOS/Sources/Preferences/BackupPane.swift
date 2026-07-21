import SwiftUI
import LillistUI
import AppKit
import UniformTypeIdentifiers
import LillistCore

/// macOS Preferences → Backups pane (issue #7). Lists the timestamped snapshot
/// zips, creates one on demand, saves a copy of any of them, and restores from
/// one — schema-gated and behind a destructive confirmation, because a restore
/// wipes iCloud and replaces it with the backup.
struct BackupPane: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var snapshots: [BackupSnapshotManager.SnapshotInfo] = []
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var restoreCandidate: BackupSnapshotManager.SnapshotInfo?
    @State private var confirmingRestore = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("Backups") {
                Button {
                    Task { await backupNow() }
                } label: {
                    if isBackingUp {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Back up now")
                    }
                }
                .disabled(isBackingUp || isRestoring)

                if snapshots.isEmpty {
                    Text("No backups yet. A snapshot is taken automatically each day, or click Back up now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots, id: \.url) { snapshot in
                        snapshotRow(snapshot)
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(statusIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await loadSnapshots() }
        .confirmationDialog(
            "Restore from this backup?",
            isPresented: $confirmingRestore,
            titleVisibility: .visible,
            presenting: restoreCandidate
        ) { candidate in
            Button("Replace Everything", role: .destructive) {
                Task { await runRestore(candidate) }
            }
            Button("Cancel", role: .cancel) { restoreCandidate = nil }
        } message: { _ in
            Text("This deletes your current tasks on this device and in iCloud — on every device signed in to this account — and replaces them with this backup. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func snapshotRow(_ snapshot: BackupSnapshotManager.SnapshotInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(snapshot.byteSize.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Save a copy…") { saveCopy(of: snapshot) }
                .controlSize(.small)
            Button("Restore…") {
                Task { await prepareRestore(snapshot) }
            }
            .controlSize(.small)
            .disabled(isRestoring)
        }
    }

    // MARK: - Actions

    private func loadSnapshots() async {
        snapshots = (try? environment.backupSnapshotManager.listSnapshots()) ?? []
    }

    private func backupNow() async {
        isBackingUp = true
        statusMessage = nil
        statusIsError = false
        defer { isBackingUp = false }
        do {
            let manager = environment.backupSnapshotManager
            _ = try await Task.detached { try manager.createSnapshot() }.value
            await loadSnapshots()
            statusMessage = String(localized: "Backup created.")
            statusIsError = false
        } catch {
            statusMessage = String(localized: "Backup failed: \(error.localizedDescription)")
            statusIsError = true
        }
    }

    private func saveCopy(of snapshot: BackupSnapshotManager.SnapshotInfo) {
        let panel = NSSavePanel()
        panel.title = "Save backup"
        panel.nameFieldStringValue = snapshot.url.lastPathComponent
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: snapshot.url, to: dest)
            statusMessage = String(localized: "Saved a copy of the backup.")
            statusIsError = false
        } catch {
            statusMessage = String(localized: "Couldn't save a copy: \(error.localizedDescription)")
            statusIsError = true
        }
    }

    private func prepareRestore(_ snapshot: BackupSnapshotManager.SnapshotInfo) async {
        statusMessage = nil
        statusIsError = false
        do {
            let pre = try await environment.backupRestoreService.preflight(.snapshotZip(snapshot.url))
            if pre.isCompatible {
                restoreCandidate = snapshot
                confirmingRestore = true
            } else {
                statusMessage = String(localized: "This backup was made with a different data version and can't be restored.")
                statusIsError = true
            }
        } catch {
            statusMessage = String(localized: "Couldn't read that backup: \(error.localizedDescription)")
            statusIsError = true
        }
    }

    private func runRestore(_ snapshot: BackupSnapshotManager.SnapshotInfo) async {
        isRestoring = true
        statusMessage = nil
        statusIsError = false
        defer { isRestoring = false; restoreCandidate = nil }
        do {
            let summary = try await environment.backupRestoreService.restore(from: .snapshotZip(snapshot.url))
            statusMessage = String(localized: "Restored \(summary.tasksInserted) tasks. Relaunch Lillist to reload.")
            statusIsError = false
        } catch {
            statusMessage = String(localized: "Restore failed: \(error.localizedDescription)")
            statusIsError = true
        }
    }
}
