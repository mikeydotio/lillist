import Foundation

/// Reads a live backup package (or an unzipped snapshot) back into the value
/// types the restore path needs (issue #7). Read-only — all writes go through
/// `TaskBackupStore`. Atomic per-file writes mean each file the reader decodes
/// is always whole.
public struct BackupPackageReader: Sendable {
    public let packageDirectory: URL
    private let tasksDirectory: URL
    /// Directory holding attachment blobs, passed to `Importer` so it can
    /// recreate `Attachment.data` on restore.
    public let assetsDirectory: URL
    private let manifestURL: URL
    private let tagsURL: URL
    private let preferencesURL: URL
    private let seriesURL: URL
    private let smartFiltersURL: URL

    public init(packageDirectory: URL) {
        self.packageDirectory = packageDirectory
        self.tasksDirectory = packageDirectory.appendingPathComponent("tasks", isDirectory: true)
        self.assetsDirectory = packageDirectory.appendingPathComponent("assets", isDirectory: true)
        self.manifestURL = packageDirectory.appendingPathComponent("manifest.json")
        self.tagsURL = packageDirectory.appendingPathComponent("tags.json")
        self.preferencesURL = packageDirectory.appendingPathComponent("preferences.json")
        self.seriesURL = packageDirectory.appendingPathComponent("series.json")
        self.smartFiltersURL = packageDirectory.appendingPathComponent("smartFilters.json")
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// The package manifest, or `nil` if absent/unreadable.
    public func readManifest() throws -> BackupPackageSchema.Manifest? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        guard !data.isEmpty else { return nil }
        return try Self.makeDecoder().decode(BackupPackageSchema.Manifest.self, from: data)
    }

    /// Decode every `tasks/<id>.json` into its `TaskBackupRecord`. Order is
    /// filesystem-dependent; callers that care sort downstream.
    public func readTaskRecords() throws -> [BackupPackageSchema.TaskBackupRecord] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: tasksDirectory.path) else { return [] }
        let decoder = Self.makeDecoder()
        let files = try fm.contentsOfDirectory(at: tasksDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return try files.map { url in
            try decoder.decode(BackupPackageSchema.TaskBackupRecord.self, from: try Data(contentsOf: url))
        }
    }

    /// Reassemble a single `ExportSchema.Document` from the package — the form
    /// `Importer.apply` consumes. Tasks, their owned journal entries and
    /// attachment metadata come from the task files; tags + preferences from the
    /// sidecars. Attachment bytes are *not* inlined — they stay on disk under
    /// `assetsDirectory`, which restore passes to the importer.
    public func assembleDocument() throws -> ExportSchema.Document {
        let records = try readTaskRecords()
        let manifest = try? readManifest()
        return ExportSchema.Document(
            version: ExportSchema.version,
            exportedAt: manifest?.updatedAt ?? Date(),
            tasks: records.map(\.task),
            tags: try readTags(),
            journalEntries: records.flatMap(\.journalEntries),
            attachments: records.flatMap(\.attachments),
            preferences: try readPreferences(),
            series: try readSeries(),
            notificationSpecs: records.flatMap(\.notificationSpecs),
            smartFilters: try readSmartFilters()
        )
    }

    private func readTags() throws -> [ExportSchema.TagDTO] {
        guard FileManager.default.fileExists(atPath: tagsURL.path) else { return [] }
        let data = try Data(contentsOf: tagsURL)
        guard !data.isEmpty else { return [] }
        return try Self.makeDecoder().decode([ExportSchema.TagDTO].self, from: data)
    }

    /// X3: absent for a package written before this plan — returns `[]`
    /// rather than throwing, matching `readTags()`'s missing-file handling.
    private func readSeries() throws -> [ExportSchema.SeriesDTO] {
        guard FileManager.default.fileExists(atPath: seriesURL.path) else { return [] }
        let data = try Data(contentsOf: seriesURL)
        guard !data.isEmpty else { return [] }
        return try Self.makeDecoder().decode([ExportSchema.SeriesDTO].self, from: data)
    }

    /// X3 (discovered): absent for a package written before this plan —
    /// returns `[]` rather than throwing, matching `readTags()`'s
    /// missing-file handling.
    private func readSmartFilters() throws -> [ExportSchema.SmartFilterDTO] {
        guard FileManager.default.fileExists(atPath: smartFiltersURL.path) else { return [] }
        let data = try Data(contentsOf: smartFiltersURL)
        guard !data.isEmpty else { return [] }
        return try Self.makeDecoder().decode([ExportSchema.SmartFilterDTO].self, from: data)
    }

    private func readPreferences() throws -> ExportSchema.PreferencesDTO {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else {
            return .fallback
        }
        let data = try Data(contentsOf: preferencesURL)
        guard !data.isEmpty else { return .fallback }
        return try Self.makeDecoder().decode(ExportSchema.PreferencesDTO.self, from: data)
    }
}
