import SwiftUI
import LillistCore
import LillistUI

/// Settings → Data Management → Backups (issue #7). Lists the timestamped
/// snapshot zips, lets the user create one on demand, share any of them, and
/// restore from one — gated on schema compatibility and behind a destructive
/// confirmation, since a restore wipes iCloud and replaces it with the backup.
struct BackupSection: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var snapshots: [BackupSnapshotManager.SnapshotInfo] = []
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var restoreCandidate: BackupSnapshotManager.SnapshotInfo?
    @State private var preflight: BackupRestoreService.Preflight?
    @State private var confirmingRestore = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Section {
            Button {
                Task { await backupNow() }
            } label: {
                if isBackingUp {
                    ProgressView()
                } else {
                    Label("Back up now", systemImage: "externaldrive.badge.plus")
                }
            }
            .disabled(isBackingUp || isRestoring)

            if snapshots.isEmpty {
                Text("No backups yet. A snapshot is taken automatically each day, or tap Back up now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshots, id: \.url) { snapshot in
                    snapshotRow(snapshot)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? RainbowPalette.cautionAmber.ink : Color.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        } header: {
            Text("Backups")
        } footer: {
            Text("Every task is saved to disk as JSON as you edit, and rolled into a daily zip. Restoring replaces all current data with the backup.")
        }
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
            ShareLink(item: snapshot.url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Share backup")

            Button {
                Task { await prepareRestore(snapshot) }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderless)
            .disabled(isRestoring)
            .accessibilityLabel("Restore from this backup")
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
            announce(String(localized: "Backup created."), isError: false)
        } catch {
            announce(String(localized: "Backup failed: \(error.localizedDescription)"), isError: true)
        }
    }

    private func prepareRestore(_ snapshot: BackupSnapshotManager.SnapshotInfo) async {
        statusMessage = nil
        statusIsError = false
        do {
            let pre = try await environment.backupRestoreService.preflight(.snapshotZip(snapshot.url))
            preflight = pre
            if pre.isCompatible {
                restoreCandidate = snapshot
                confirmingRestore = true
            } else {
                announce(String(localized: "This backup was made with a different data version and can't be restored."), isError: true)
            }
        } catch {
            announce(String(localized: "Couldn't read that backup: \(error.localizedDescription)"), isError: true)
        }
    }

    private func runRestore(_ snapshot: BackupSnapshotManager.SnapshotInfo) async {
        isRestoring = true
        statusMessage = nil
        statusIsError = false
        defer { isRestoring = false; restoreCandidate = nil }
        do {
            let summary = try await environment.backupRestoreService.restore(from: .snapshotZip(snapshot.url))
            announce(String(localized: "Restored \(summary.tasksInserted) tasks. Relaunch Lillist to reload."), isError: false)
        } catch {
            announce(String(localized: "Restore failed: \(error.localizedDescription)"), isError: true)
        }
    }

    private func announce(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
        AccessibilityAnnouncements.post(message, priority: isError ? .high : .low)
    }
}
