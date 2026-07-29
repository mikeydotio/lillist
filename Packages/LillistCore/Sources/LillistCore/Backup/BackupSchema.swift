import Foundation

/// On-disk layout contract for the live backup *package* (issue #7).
///
/// `version` describes the directory/file *layout* — the `tasks/<id>.json`,
/// `tags.json`, `preferences.json`, `assets/`, `manifest.json` shape — and is
/// **distinct** from ``ExportSchema/version`` (the full-bundle document DTO) and
/// ``CloudKitSchema/currentVersion`` (the per-task CloudKit record shape). Bump
/// only when the on-disk layout itself changes.
public enum BackupPackageSchema {
    /// v2 (X3): `TaskBackupRecord` gains `notificationSpecs` (task-owned, so
    /// it lives in the per-task file rather than a sidecar); the package
    /// gains two new sidecar files, `series.json`/`smartFilters.json`
    /// (`TaskBackupStore`/`BackupPackageReader`). A v1 package's task files
    /// simply omit the new key — see `TaskBackupRecord`'s custom
    /// `init(from:)` — and its missing sidecars are read as `[]`.
    public static let version = 2

    /// One self-contained task file: the task plus everything it *owns*
    /// (journal entries, attachment metadata, reminders). Shared entities
    /// (tags, preferences, series, smart filters) live in sidecar files;
    /// attachment binaries live in `assets/` and are referenced by each
    /// `AttachmentDTO.dataPath`.
    public struct TaskBackupRecord: Codable, Sendable, Equatable {
        /// `BackupPackageSchema.version` at write time.
        public var backupSchemaVersion: Int
        /// The task's persisted `CloudKitSchema` version (issue #7 gate value).
        public var cloudKitSchemaVersion: Int
        public var task: ExportSchema.TaskDTO
        public var journalEntries: [ExportSchema.JournalEntryDTO]
        public var attachments: [ExportSchema.AttachmentDTO]
        /// X3: this task's reminders. Absent from v1 task files — decodes as `[]`.
        public var notificationSpecs: [ExportSchema.NotificationSpecDTO] = []

        public init(
            backupSchemaVersion: Int,
            cloudKitSchemaVersion: Int,
            task: ExportSchema.TaskDTO,
            journalEntries: [ExportSchema.JournalEntryDTO],
            attachments: [ExportSchema.AttachmentDTO],
            notificationSpecs: [ExportSchema.NotificationSpecDTO] = []
        ) {
            self.backupSchemaVersion = backupSchemaVersion
            self.cloudKitSchemaVersion = cloudKitSchemaVersion
            self.task = task
            self.journalEntries = journalEntries
            self.attachments = attachments
            self.notificationSpecs = notificationSpecs
        }
    }

    /// Package-level summary written to `manifest.json` on every update. The
    /// restore preflight reads `cloudKitSchemaVersion` from here to gate
    /// compatibility without scanning every task file.
    public struct Manifest: Codable, Sendable, Equatable {
        public var backupSchemaVersion: Int
        public var cloudKitSchemaVersion: Int
        public var updatedAt: Date
        public var taskCount: Int

        public init(
            backupSchemaVersion: Int,
            cloudKitSchemaVersion: Int,
            updatedAt: Date,
            taskCount: Int
        ) {
            self.backupSchemaVersion = backupSchemaVersion
            self.cloudKitSchemaVersion = cloudKitSchemaVersion
            self.updatedAt = updatedAt
            self.taskCount = taskCount
        }
    }
}

extension BackupPackageSchema.TaskBackupRecord {
    private enum CodingKeys: String, CodingKey {
        case backupSchemaVersion, cloudKitSchemaVersion, task, journalEntries,
             attachments, notificationSpecs
    }

    /// Default-safe decode for `notificationSpecs` (X3, v2) — a v1 task file
    /// omits the key; default to `[]` rather than throwing `keyNotFound`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            backupSchemaVersion: try c.decode(Int.self, forKey: .backupSchemaVersion),
            cloudKitSchemaVersion: try c.decode(Int.self, forKey: .cloudKitSchemaVersion),
            task: try c.decode(ExportSchema.TaskDTO.self, forKey: .task),
            journalEntries: try c.decode([ExportSchema.JournalEntryDTO].self, forKey: .journalEntries),
            attachments: try c.decode([ExportSchema.AttachmentDTO].self, forKey: .attachments),
            notificationSpecs: try c.decodeIfPresent([ExportSchema.NotificationSpecDTO].self, forKey: .notificationSpecs) ?? []
        )
    }
}
