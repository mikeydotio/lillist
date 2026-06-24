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

    public struct TaskDTO: Codable, Sendable, Equatable {
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
        /// CloudKit schema version this task record conforms to (issue #7).
        /// Defaults to `0` so bundles written before this field existed decode
        /// cleanly (see the custom `init(from:)` below). The `= 0` default also
        /// keeps the synthesized memberwise init backward-compatible for callers
        /// that predate the field.
        public var schemaVersion: Int = 0
    }

    public struct TagDTO: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var tintColor: String?
        public var parentID: UUID?
        public var position: Double
    }

    public struct JournalEntryDTO: Codable, Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID?
        public var kind: Int
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }

    public struct AttachmentDTO: Codable, Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID?
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

    public struct PreferencesDTO: Codable, Sendable, Equatable {
        public var defaultAllDayHour: Int16
        public var defaultAllDayMinute: Int16
        public var morningSummaryEnabled: Bool
        public var morningSummaryHour: Int16
        public var morningSummaryMinute: Int16
        public var trashRetentionDays: Int16
        public var defaultTaskListSort: String
    }
}

extension ExportSchema.TaskDTO {
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, status, start, startHasTime, deadline,
             deadlineHasTime, position, isPinned, parentID, tagIDs,
             createdAt, modifiedAt, closedAt, deletedAt, schemaVersion
    }

    /// Default-safe decode. `schemaVersion` was added after v1, so bundles that
    /// predate it omit the key — decode it as `0` ("pre-versioning / unknown")
    /// rather than throwing `keyNotFound`. The synthesized memberwise init and
    /// `encode(to:)` are preserved (this lives in an extension; `encode` uses
    /// the `CodingKeys` above, which includes `schemaVersion`).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            notes: try c.decode(String.self, forKey: .notes),
            status: try c.decode(Int.self, forKey: .status),
            start: try c.decodeIfPresent(Date.self, forKey: .start),
            startHasTime: try c.decode(Bool.self, forKey: .startHasTime),
            deadline: try c.decodeIfPresent(Date.self, forKey: .deadline),
            deadlineHasTime: try c.decode(Bool.self, forKey: .deadlineHasTime),
            position: try c.decode(Double.self, forKey: .position),
            isPinned: try c.decode(Bool.self, forKey: .isPinned),
            parentID: try c.decodeIfPresent(UUID.self, forKey: .parentID),
            tagIDs: try c.decode([UUID].self, forKey: .tagIDs),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt),
            modifiedAt: try c.decodeIfPresent(Date.self, forKey: .modifiedAt),
            closedAt: try c.decodeIfPresent(Date.self, forKey: .closedAt),
            deletedAt: try c.decodeIfPresent(Date.self, forKey: .deletedAt),
            schemaVersion: try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        )
    }
}
