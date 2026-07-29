import Foundation

/// Versioned export schema. Bump `version` for any incompatible change.
public enum ExportSchema {
    /// v2 (X3): adds `series`, `notificationSpecs`, `smartFilters` to
    /// `Document`; `archivedAt`/`seriesID` to `TaskDTO`; `defaultTagTintHex`
    /// to `PreferencesDTO`. All additions decode-with-default on older
    /// bundles (absent key → `[]`/`nil`/the model's own default) — see each
    /// type's custom `init(from:)` below. See
    /// `docs/superpowers/plans/2026-07-28-plan-1d-export-schema-completeness.md`
    /// for the full version-compat matrix.
    public static let version = 2

    public struct Document: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var tasks: [TaskDTO]
        public var tags: [TagDTO]
        public var journalEntries: [JournalEntryDTO]
        public var attachments: [AttachmentDTO]
        public var preferences: PreferencesDTO
        /// Recurrence series (X3). Absent from v1 bundles — decodes as `[]`.
        public var series: [SeriesDTO] = []
        /// Reminders (X3). Absent from v1 bundles — decodes as `[]`.
        public var notificationSpecs: [NotificationSpecDTO] = []
        /// Saved smart filters — every attribute of `SmartFilter` had zero
        /// export mapping before this plan (discovered via the model-derived
        /// completeness test, not a named review finding on its own; see the
        /// plan doc's *Scope note*). Absent from v1 bundles — decodes as `[]`.
        public var smartFilters: [SmartFilterDTO] = []

        public init(
            version: Int,
            exportedAt: Date,
            tasks: [TaskDTO],
            tags: [TagDTO],
            journalEntries: [JournalEntryDTO],
            attachments: [AttachmentDTO],
            preferences: PreferencesDTO,
            series: [SeriesDTO] = [],
            notificationSpecs: [NotificationSpecDTO] = [],
            smartFilters: [SmartFilterDTO] = []
        ) {
            self.version = version
            self.exportedAt = exportedAt
            self.tasks = tasks
            self.tags = tags
            self.journalEntries = journalEntries
            self.attachments = attachments
            self.preferences = preferences
            self.series = series
            self.notificationSpecs = notificationSpecs
            self.smartFilters = smartFilters
        }
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
        /// X3: when this task is archived. Absent from v1 bundles — decodes
        /// as `nil`.
        public var archivedAt: Date? = nil
        /// X3: the id of the `Series` this task is an instance of (the "many"
        /// side of `Series.instances` carries the FK, matching `parentID`).
        /// Absent from v1 bundles — decodes as `nil`.
        public var seriesID: UUID? = nil
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
        /// Real, CloudKit-synced, account-level preference that had no
        /// export mapping before this plan — distinct from the five fields
        /// Plan 21 deliberately partitioned into device-local
        /// `DevicePreferencesStore` (`crashPromptsEnabled`,
        /// `hasCompletedOnboarding`, `quickCaptureEnabled`,
        /// `quickCaptureHotkey`, `statusBarItemVisible`), which stay
        /// excluded by design. Absent from v1 bundles — decodes as the Core
        /// Data model's own default, `"#7F8FA6"`.
        public var defaultTagTintHex: String = "#7F8FA6"

        public init(
            defaultAllDayHour: Int16,
            defaultAllDayMinute: Int16,
            morningSummaryEnabled: Bool,
            morningSummaryHour: Int16,
            morningSummaryMinute: Int16,
            trashRetentionDays: Int16,
            defaultTaskListSort: String,
            defaultTagTintHex: String = "#7F8FA6"
        ) {
            self.defaultAllDayHour = defaultAllDayHour
            self.defaultAllDayMinute = defaultAllDayMinute
            self.morningSummaryEnabled = morningSummaryEnabled
            self.morningSummaryHour = morningSummaryHour
            self.morningSummaryMinute = morningSummaryMinute
            self.trashRetentionDays = trashRetentionDays
            self.defaultTaskListSort = defaultTaskListSort
            self.defaultTagTintHex = defaultTagTintHex
        }

        /// Shared fallback used by every reader that must produce a
        /// `PreferencesDTO` without a live `AppPreferences` row to project
        /// from (an empty/never-touched store, or a package predating the
        /// preferences sidecar). Mirrors the Core Data model's own defaults
        /// (`AppPreferences`'s `defaultValueString`s). Single source of
        /// truth — do not re-duplicate these literals at call sites.
        public static let fallback = PreferencesDTO(
            defaultAllDayHour: 9,
            defaultAllDayMinute: 0,
            morningSummaryEnabled: true,
            morningSummaryHour: 9,
            morningSummaryMinute: 0,
            trashRetentionDays: 30,
            defaultTaskListSort: "manualPosition",
            defaultTagTintHex: "#7F8FA6"
        )
    }

    /// X3: a recurrence series. `Series` had zero export/backup mapping
    /// before this plan.
    public struct SeriesDTO: Codable, Sendable, Equatable {
        public var id: UUID
        /// FK to the task this series was created from. `Series.seedTask`
        /// is optional in the model; a bundle whose seed task is absent
        /// (neither in the bundle nor the destination store) still imports
        /// the series with `seedTaskID` resolving to `nil` on import — the
        /// series' rule and its instance tasks (wired independently via
        /// `TaskDTO.seriesID`) remain valid and are far more valuable to
        /// preserve than a single dangling seed pointer.
        public var seedTaskID: UUID?
        public var rule: RecurrenceRule?
        public var nextOccurrenceAfter: Date?

        public init(id: UUID, seedTaskID: UUID?, rule: RecurrenceRule?, nextOccurrenceAfter: Date?) {
            self.id = id
            self.seedTaskID = seedTaskID
            self.rule = rule
            self.nextOccurrenceAfter = nextOccurrenceAfter
        }
    }

    /// X3: a scheduled reminder. `NotificationSpec` had zero export/backup
    /// mapping before this plan.
    ///
    /// `lastFiredAt` round-trips as-is (import does not reset it) — see the
    /// plan doc's *"lastFiredAt — decided directly, no council needed"*
    /// section: it is already a real CloudKit-mirrored cross-device de-dup
    /// field (`NotificationScheduler.computeDesiredRequests`), and
    /// `resetAndReseedFromThisDevice` converging every device on this
    /// device's exact state is the field's *correct* behavior, not a bug.
    public struct NotificationSpecDTO: Codable, Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID?
        public var kind: Int
        public var offsetMinutes: Int32?
        public var fireDate: Date?
        public var lastFiredAt: Date?
        public var snoozedUntil: Date?
        public var createdAt: Date?

        public init(
            id: UUID,
            taskID: UUID?,
            kind: Int,
            offsetMinutes: Int32?,
            fireDate: Date?,
            lastFiredAt: Date?,
            snoozedUntil: Date?,
            createdAt: Date?
        ) {
            self.id = id
            self.taskID = taskID
            self.kind = kind
            self.offsetMinutes = offsetMinutes
            self.fireDate = fireDate
            self.lastFiredAt = lastFiredAt
            self.snoozedUntil = snoozedUntil
            self.createdAt = createdAt
        }
    }

    /// A saved smart filter — `SmartFilter` had zero export/backup mapping
    /// before this plan (discovered via the model-derived completeness
    /// test; see the plan doc's *Scope note*). `predicateGroup` decodes
    /// leniently (`nil` on malformed JSON), matching `SeriesDTO.rule`'s
    /// resilience pattern.
    public struct SmartFilterDTO: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var predicateGroup: PredicateGroup?
        public var tintColor: String?
        public var sortField: String
        public var sortAscending: Bool
        public var isPinned: Bool
        public var position: Double
        public var createdAt: Date?
        public var modifiedAt: Date?

        public init(
            id: UUID,
            name: String,
            predicateGroup: PredicateGroup?,
            tintColor: String?,
            sortField: String,
            sortAscending: Bool,
            isPinned: Bool,
            position: Double,
            createdAt: Date?,
            modifiedAt: Date?
        ) {
            self.id = id
            self.name = name
            self.predicateGroup = predicateGroup
            self.tintColor = tintColor
            self.sortField = sortField
            self.sortAscending = sortAscending
            self.isPinned = isPinned
            self.position = position
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
        }
    }
}

extension ExportSchema.TaskDTO {
    private enum CodingKeys: String, CodingKey {
        case id, title, notes, status, start, startHasTime, deadline,
             deadlineHasTime, position, isPinned, parentID, tagIDs,
             createdAt, modifiedAt, closedAt, deletedAt, schemaVersion,
             archivedAt, seriesID
    }

    /// Default-safe decode. `schemaVersion` was added after v1, so bundles that
    /// predate it omit the key — decode it as `0` ("pre-versioning / unknown")
    /// rather than throwing `keyNotFound`. `archivedAt`/`seriesID` (X3, v2)
    /// get the identical treatment. The synthesized memberwise init and
    /// `encode(to:)` are preserved (this lives in an extension; `encode` uses
    /// the `CodingKeys` above, which includes every field).
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
            schemaVersion: try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0,
            archivedAt: try c.decodeIfPresent(Date.self, forKey: .archivedAt),
            seriesID: try c.decodeIfPresent(UUID.self, forKey: .seriesID)
        )
    }
}

extension ExportSchema.PreferencesDTO {
    private enum CodingKeys: String, CodingKey {
        case defaultAllDayHour, defaultAllDayMinute, morningSummaryEnabled,
             morningSummaryHour, morningSummaryMinute, trashRetentionDays,
             defaultTaskListSort, defaultTagTintHex
    }

    /// Default-safe decode for `defaultTagTintHex` (X3, v2) — a v1 bundle
    /// omits the key; default to the Core Data model's own default rather
    /// than throwing `keyNotFound`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultAllDayHour: try c.decode(Int16.self, forKey: .defaultAllDayHour),
            defaultAllDayMinute: try c.decode(Int16.self, forKey: .defaultAllDayMinute),
            morningSummaryEnabled: try c.decode(Bool.self, forKey: .morningSummaryEnabled),
            morningSummaryHour: try c.decode(Int16.self, forKey: .morningSummaryHour),
            morningSummaryMinute: try c.decode(Int16.self, forKey: .morningSummaryMinute),
            trashRetentionDays: try c.decode(Int16.self, forKey: .trashRetentionDays),
            defaultTaskListSort: try c.decode(String.self, forKey: .defaultTaskListSort),
            defaultTagTintHex: try c.decodeIfPresent(String.self, forKey: .defaultTagTintHex) ?? "#7F8FA6"
        )
    }
}

extension ExportSchema.Document {
    private enum CodingKeys: String, CodingKey {
        case version, exportedAt, tasks, tags, journalEntries, attachments,
             preferences, series, notificationSpecs, smartFilters
    }

    /// Default-safe decode for `series`/`notificationSpecs`/`smartFilters`
    /// (X3, v2) — a v1 bundle omits all three keys; default to `[]` rather
    /// than throwing `keyNotFound`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            exportedAt: try c.decode(Date.self, forKey: .exportedAt),
            tasks: try c.decode([ExportSchema.TaskDTO].self, forKey: .tasks),
            tags: try c.decode([ExportSchema.TagDTO].self, forKey: .tags),
            journalEntries: try c.decode([ExportSchema.JournalEntryDTO].self, forKey: .journalEntries),
            attachments: try c.decode([ExportSchema.AttachmentDTO].self, forKey: .attachments),
            preferences: try c.decode(ExportSchema.PreferencesDTO.self, forKey: .preferences),
            series: try c.decodeIfPresent([ExportSchema.SeriesDTO].self, forKey: .series) ?? [],
            notificationSpecs: try c.decodeIfPresent([ExportSchema.NotificationSpecDTO].self, forKey: .notificationSpecs) ?? [],
            smartFilters: try c.decodeIfPresent([ExportSchema.SmartFilterDTO].self, forKey: .smartFilters) ?? []
        )
    }
}
