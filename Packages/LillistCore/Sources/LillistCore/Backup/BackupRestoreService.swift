import Foundation

/// The destructive primitive a restore needs: wipe local **and** iCloud data and
/// rebuild an empty store. `DataStoreResetService` is the production conformer;
/// tests inject a fake so they never touch a real CloudKit zone.
@MainActor
public protocol BackupDataResetting {
    func resetAllData() async throws
}

extension DataStoreResetService: BackupDataResetting {}

/// Restores all data from a backup package or snapshot zip (issue #7).
///
/// Restore is **destructive and schema-gated**: it only proceeds when the
/// backup's CloudKit schema version matches this build's, then wipes local +
/// iCloud data (`BackupDataResetting`) and replaces it with the backup's
/// contents via the atomic `Importer`. `@MainActor` because the reset primitive
/// is main-actor isolated (it drives a SwiftUI-facing service).
///
/// Issue #71: on success, also broadcasts a `.resetAndReseed` control event
/// via `ResetPropagator` (when configured) — a restore replaces this
/// device's data with the backup's contents, which is exactly the "converge
/// every other device on what's now here" case `resetAndReseedFromThisDevice()`
/// handles for a live device. Before this, a restore's cross-device
/// consequences were entirely silent (the same root cause "Reset Everywhere"
/// had: `resetAllData()` only ever erased the CloudKit zone, which does not
/// propagate — see `DataStoreResetService`'s doc comment for the full
/// root-cause writeup).
@MainActor
public final class BackupRestoreService {
    private let reset: any BackupDataResetting
    private let importer: Importer
    private let preferences: PreferencesStore
    private let packageDirectory: URL
    /// Issue #66: restore is a major, destructive, hard-to-reverse operation
    /// that — before this — left no diagnostic trace at all; the #66
    /// investigation could not confirm whether or when a restore happened on
    /// the affected device. `nil` (the default) preserves prior behavior for
    /// any caller that doesn't wire a sink.
    private let diagnosticLog: DiagnosticSink?
    private let process: DiagProcess
    /// Cross-device "converge to current iCloud state" signal (issue #71).
    /// `nil` → restore still succeeds locally but doesn't notify peers
    /// (test/legacy callers).
    private let propagator: ResetPropagator?

    public init(
        reset: any BackupDataResetting,
        importer: Importer,
        preferences: PreferencesStore,
        packageDirectory: URL,
        diagnosticLog: DiagnosticSink? = nil,
        process: DiagProcess = .app,
        propagator: ResetPropagator? = nil
    ) {
        self.reset = reset
        self.importer = importer
        self.preferences = preferences
        self.packageDirectory = packageDirectory
        self.diagnosticLog = diagnosticLog
        self.process = process
        self.propagator = propagator
    }

    /// What to restore from: the live package, or a specific snapshot zip.
    public enum RestoreSource: Sendable, Equatable {
        case livePackage
        case snapshotZip(URL)
    }

    /// A non-mutating compatibility report the UI uses to gate the restore
    /// button before showing the destructive confirmation.
    public struct Preflight: Sendable, Equatable {
        public let fileCloudKitSchemaVersion: Int
        public let currentCloudKitSchemaVersion: Int
        public let taskCount: Int
        public var isCompatible: Bool { fileCloudKitSchemaVersion == currentCloudKitSchemaVersion }

        public init(fileCloudKitSchemaVersion: Int, currentCloudKitSchemaVersion: Int, taskCount: Int) {
            self.fileCloudKitSchemaVersion = fileCloudKitSchemaVersion
            self.currentCloudKitSchemaVersion = currentCloudKitSchemaVersion
            self.taskCount = taskCount
        }
    }

    /// Inspect a source's schema version + size **without mutating anything**.
    public func preflight(_ source: RestoreSource) async throws -> Preflight {
        let resolved = try resolveReader(source)
        defer { resolved.cleanup() }
        return try Self.preflight(reader: resolved.reader)
    }

    /// Schema-gated, destructive restore. Throws `schemaVersionMismatch` if the
    /// backup's version differs from this build's (the UI should have gated
    /// already — this is defense in depth). On success the store contains
    /// exactly the backup's tasks, tags, journal entries, attachments, and the
    /// captured preferences.
    @discardableResult
    public func restore(from source: RestoreSource) async throws -> Importer.ImportSummary {
        do {
            let resolved = try resolveReader(source)
            defer { resolved.cleanup() }
            let reader = resolved.reader

            let pre = try Self.preflight(reader: reader)
            guard pre.isCompatible else {
                let error = LillistError.schemaVersionMismatch(
                    found: pre.fileCloudKitSchemaVersion,
                    current: pre.currentCloudKitSchemaVersion
                )
                await emit(source: source, outcome: "incompatible", summary: nil)
                throw error
            }

            // Wipe local + iCloud, rebuild empty.
            try await reset.resetAllData()

            // Replace with the backup's contents (atomic, all-or-nothing).
            let document = try reader.assembleDocument()
            let summary = try await importer.apply(
                document: document,
                policy: .replaceExisting,
                assetsDirectory: reader.assetsDirectory
            )
            // Importer does not touch preferences — apply the captured set here.
            try await applyPreferences(document.preferences)
            await emit(source: source, outcome: "completed", summary: summary)
            // This device's data just became the account's new truth — tell
            // every other known device to converge on it too.
            propagator?.broadcast(.resetAndReseed)
            return summary
        } catch {
            // The `incompatible` path already emitted above (it needs its own
            // outcome label, not the generic "failed"); every OTHER throw —
            // reset failure, corrupt package, import failure — lands here.
            if case LillistError.schemaVersionMismatch = error {
                throw error
            }
            await emit(source: source, outcome: "failed", summary: nil)
            throw error
        }
    }

    /// Every return path — success, schema refusal, or any other failure —
    /// routes through here, so a restore never completes (or fails) without
    /// a matching diagnostic record. Issue #66's investigation had no way to
    /// confirm whether or when a restore happened; this closes that gap.
    private func emit(source: RestoreSource, outcome: String, summary: Importer.ImportSummary?) async {
        guard let diagnosticLog else { return }
        var payload: [String: DiagValue] = [
            "source": .string(sourceName(source)),
            "outcome": .string(outcome)
        ]
        if let summary {
            payload["tasksInserted"] = .int(summary.tasksInserted)
            payload["tasksUpdated"] = .int(summary.tasksUpdated)
            payload["tasksSkipped"] = .int(summary.tasksSkipped)
        }
        await diagnosticLog.log(DiagnosticEvent(
            at: Date(), seq: 0, process: process, category: .data,
            name: "backup.restore", payload: payload
        ))
    }

    private func sourceName(_ source: RestoreSource) -> String {
        switch source {
        case .livePackage: return "livePackage"
        case .snapshotZip: return "snapshotZip"
        }
    }

    // MARK: - Internals

    private struct ResolvedReader {
        let reader: BackupPackageReader
        let tempDirectory: URL?
        func cleanup() {
            if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        }
    }

    private func resolveReader(_ source: RestoreSource) throws -> ResolvedReader {
        switch source {
        case .livePackage:
            return ResolvedReader(reader: BackupPackageReader(packageDirectory: packageDirectory), tempDirectory: nil)
        case .snapshotZip(let zipURL):
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("lillist-restore-\(UUID().uuidString)", isDirectory: true)
            try BackupSnapshotManager.unzip(zipURL, to: temp)
            return ResolvedReader(reader: BackupPackageReader(packageDirectory: temp), tempDirectory: temp)
        }
    }

    private static func preflight(reader: BackupPackageReader) throws -> Preflight {
        let manifest = try reader.readManifest()
        let records = try reader.readTaskRecords()
        // Prefer the manifest; fall back to the first task record; an empty
        // package with no manifest is treated as current-compatible.
        let fileVersion = manifest?.cloudKitSchemaVersion
            ?? records.first?.cloudKitSchemaVersion
            ?? CloudKitSchema.currentVersion
        let count = manifest?.taskCount ?? records.count
        return Preflight(
            fileCloudKitSchemaVersion: fileVersion,
            currentCloudKitSchemaVersion: CloudKitSchema.currentVersion,
            taskCount: count
        )
    }

    private func applyPreferences(_ dto: ExportSchema.PreferencesDTO) async throws {
        try await preferences.update { prefs in
            prefs.defaultAllDayHour = dto.defaultAllDayHour
            prefs.defaultAllDayMinute = dto.defaultAllDayMinute
            prefs.morningSummaryEnabled = dto.morningSummaryEnabled
            prefs.morningSummaryHour = dto.morningSummaryHour
            prefs.morningSummaryMinute = dto.morningSummaryMinute
            prefs.trashRetentionDays = dto.trashRetentionDays
            if let sort = SortField(rawValue: dto.defaultTaskListSort) {
                prefs.defaultTaskListSort = sort
            }
        }
    }
}
