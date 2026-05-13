import Foundation

/// Versioned export schema. Bump `version` for any incompatible change.
public enum ExportSchema {
    public static let version = 1

    public struct Document: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var tasks: [TaskDTO]
        public var tags: [TagDTO]
        public var journalEntries: [JournalEntryDTO]
        public var attachments: [AttachmentDTO]
        public var preferences: PreferencesDTO
    }

    public struct TaskDTO: Codable, Sendable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Int
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var position: Double
        public var isPinned: Bool
        public var parentID: UUID?
        public var tagIDs: [UUID]
        public var createdAt: Date?
        public var modifiedAt: Date?
        public var closedAt: Date?
        public var deletedAt: Date?
    }

    public struct TagDTO: Codable, Sendable {
        public var id: UUID
        public var name: String
        public var tintColor: String?
        public var parentID: UUID?
        public var position: Double
    }

    public struct JournalEntryDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID
        public var kind: Int
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public struct AttachmentDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID
        public var journalEntryID: UUID?
        public var kind: Int
        public var filename: String
        public var uti: String
        public var byteSize: Int64
        /// Relative path under the export's `assets/` folder. Nil for link previews.
        public var dataPath: String?
        public var linkPreviewJSON: String?
        public var createdAt: Date?
    }

    public struct PreferencesDTO: Codable, Sendable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: String
    }
}
