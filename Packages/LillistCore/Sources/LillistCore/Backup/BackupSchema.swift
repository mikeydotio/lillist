import Foundation

/// On-disk layout contract for the live backup *package* (issue #7).
///
/// `version` describes the directory/file *layout* — the `tasks/<id>.json`,
/// `tags.json`, `preferences.json`, `assets/`, `manifest.json` shape — and is
/// **distinct** from ``ExportSchema/version`` (the full-bundle document DTO) and
/// ``CloudKitSchema/currentVersion`` (the per-task CloudKit record shape). Bump
/// only when the on-disk layout itself changes.
public enum BackupPackageSchema {
    public static let version = 1

    /// One self-contained task file: the task plus everything it *owns*
    /// (journal entries, attachment metadata). Shared entities (tags,
    /// preferences) live in sidecar files; attachment binaries live in
    /// `assets/` and are referenced by each `AttachmentDTO.dataPath`.
    public struct TaskBackupRecord: Codable, Sendable, Equatable {
        /// `BackupPackageSchema.version` at write time.
        public var backupSchemaVersion: Int
        /// The task's persisted `CloudKitSchema` version (issue #7 gate value).
        public var cloudKitSchemaVersion: Int
        public var task: ExportSchema.TaskDTO
        public var journalEntries: [ExportSchema.JournalEntryDTO]
        public var attachments: [ExportSchema.AttachmentDTO]

        public init(
            backupSchemaVersion: Int,
            cloudKitSchemaVersion: Int,
            task: ExportSchema.TaskDTO,
            journalEntries: [ExportSchema.JournalEntryDTO],
            attachments: [ExportSchema.AttachmentDTO]
        ) {
            self.backupSchemaVersion = backupSchemaVersion
            self.cloudKitSchemaVersion = cloudKitSchemaVersion
            self.task = task
            self.journalEntries = journalEntries
            self.attachments = attachments
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
