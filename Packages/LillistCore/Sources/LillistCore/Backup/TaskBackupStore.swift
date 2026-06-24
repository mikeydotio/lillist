import Foundation

/// Owns all writes to the live backup *package* directory (issue #7).
///
/// An `actor` so every disk mutation to the package is serialized onto one
/// executor: no two saves race the same `<id>.json`, and a snapshot zip (which
/// also hops through this actor) never captures a half-written file. Callers
/// hand it fully-formed `Sendable` value types — never managed objects — so the
/// Core Data view-context queue is never blocked on disk I/O.
///
/// On-disk layout under `packageDirectory`:
/// ```
/// manifest.json
/// tags.json
/// preferences.json
/// tasks/<taskID>.json     (one TaskBackupRecord each)
/// assets/<attachmentID>-<filename>
/// ```
public actor TaskBackupStore {
    public let packageDirectory: URL
    private let tasksDirectory: URL
    private let assetsDirectory: URL
    private let manifestURL: URL
    private let tagsURL: URL
    private let preferencesURL: URL

    /// A binary attachment blob staged for the package's `assets/` folder.
    public struct PendingAsset: Sendable, Equatable {
        /// Filename under `assets/` (matches an `AttachmentDTO.dataPath` tail).
        public let filename: String
        public let bytes: Data
        public init(filename: String, bytes: Data) {
            self.filename = filename
            self.bytes = bytes
        }
    }

    public init(packageDirectory: URL) {
        self.packageDirectory = packageDirectory
        self.tasksDirectory = packageDirectory.appendingPathComponent("tasks", isDirectory: true)
        self.assetsDirectory = packageDirectory.appendingPathComponent("assets", isDirectory: true)
        self.manifestURL = packageDirectory.appendingPathComponent("manifest.json")
        self.tagsURL = packageDirectory.appendingPathComponent("tags.json")
        self.preferencesURL = packageDirectory.appendingPathComponent("preferences.json")
    }

    // MARK: - Encoding

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Directory lifecycle

    /// Create the package + `tasks/` + `assets/` directories if absent. Safe to
    /// call repeatedly.
    public func prepareDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tasksDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
    }

    /// True when the package holds no task files yet (used to decide whether a
    /// first-run seed is needed).
    public func isEmpty() -> Bool {
        (try? taskFileCount()) ?? 0 == 0
    }

    /// Number of `<id>.json` files currently in `tasks/`.
    public func taskFileCount() throws -> Int {
        try taskFileIDs().count
    }

    /// The UUIDs of every `<id>.json` file currently in `tasks/`. Used by the
    /// remote reconcile to set-difference against the live store and prune files
    /// for tasks deleted on another device.
    public func taskFileIDs() throws -> Set<UUID> {
        let fm = FileManager.default
        guard fm.fileExists(atPath: tasksDirectory.path) else { return [] }
        return Set(
            try fm.contentsOfDirectory(atPath: tasksDirectory.path)
                .filter { $0.hasSuffix(".json") }
                .compactMap { UUID(uuidString: ($0 as NSString).deletingPathExtension) }
        )
    }

    // MARK: - Writes

    /// Write/overwrite each task's `<id>.json` and stage its attachment blobs
    /// into `assets/`. Atomic per file — a reader never sees a torn record.
    public func upsert(_ records: [BackupPackageSchema.TaskBackupRecord], assets: [PendingAsset]) throws {
        try prepareDirectories()
        let encoder = Self.makeEncoder()
        for record in records {
            let data = try encoder.encode(record)
            try data.write(to: taskFileURL(for: record.task.id), options: [.atomic])
        }
        for asset in assets {
            try asset.bytes.write(to: assetsDirectory.appendingPathComponent(asset.filename), options: [.atomic])
        }
    }

    /// Delete the files for `taskIDs`, plus the asset blobs those task records
    /// referenced (so removing a task doesn't orphan its attachment bytes).
    public func remove(taskIDs: [UUID]) throws {
        let fm = FileManager.default
        let decoder = Self.makeDecoder()
        for id in taskIDs {
            let url = taskFileURL(for: id)
            // Best-effort: read the record first so we can clean its assets.
            if let data = try? Data(contentsOf: url),
               let record = try? decoder.decode(BackupPackageSchema.TaskBackupRecord.self, from: data) {
                for attachment in record.attachments {
                    guard let path = attachment.dataPath else { continue }
                    let assetURL = assetsDirectory.appendingPathComponent((path as NSString).lastPathComponent)
                    try? fm.removeItem(at: assetURL)
                }
            }
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }

    /// Replace the entire package contents with `records` + `assets` + sidecars.
    /// Clears `tasks/` and `assets/` first, so this also reclaims any orphaned
    /// files. Used to seed the package on first run and to repair drift.
    public func replaceAll(
        records: [BackupPackageSchema.TaskBackupRecord],
        assets: [PendingAsset],
        tags: [ExportSchema.TagDTO],
        preferences: ExportSchema.PreferencesDTO,
        cloudKitSchemaVersion: Int,
        updatedAt: Date
    ) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: tasksDirectory)
        try? fm.removeItem(at: assetsDirectory)
        try prepareDirectories()
        try upsert(records, assets: assets)
        try writeSidecars(tags: tags, preferences: preferences)
        try writeManifest(BackupPackageSchema.Manifest(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: cloudKitSchemaVersion,
            updatedAt: updatedAt,
            taskCount: records.count
        ))
    }

    /// Write the shared `tags.json` + `preferences.json` sidecars atomically.
    public func writeSidecars(tags: [ExportSchema.TagDTO], preferences: ExportSchema.PreferencesDTO) throws {
        try prepareDirectories()
        let encoder = Self.makeEncoder()
        try encoder.encode(tags).write(to: tagsURL, options: [.atomic])
        try encoder.encode(preferences).write(to: preferencesURL, options: [.atomic])
    }

    /// Write `manifest.json` atomically.
    public func writeManifest(_ manifest: BackupPackageSchema.Manifest) throws {
        try prepareDirectories()
        try Self.makeEncoder().encode(manifest).write(to: manifestURL, options: [.atomic])
    }

    // MARK: - Paths

    private func taskFileURL(for id: UUID) -> URL {
        tasksDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}
