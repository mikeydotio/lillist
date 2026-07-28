import Foundation
import CoreData

/// Projects Core Data managed objects into the value-type DTOs used by both the
/// full-bundle `Exporter` and the live backup package (`TaskBackupStore` /
/// `LocalBackupCoordinator`). Centralizing the mapping keeps the two paths from
/// drifting (DRY) and keeps the "read managed objects into `Sendable` values
/// *inside* `perform`" discipline in one reviewed place.
///
/// Every function is `nonisolated` and only touches the managed object it is
/// handed — callers must invoke them inside the owning context's `perform`
/// block. Only value types are returned, so nothing managed escapes.
enum BackupRecordProjector {
    /// Stable on-disk filename for an attachment's binary blob, deduped by the
    /// attachment's UUID. Matches the historical `Exporter` naming so existing
    /// asset paths are unchanged.
    static func assetFilename(for m: Attachment) -> String {
        "\(m.id?.uuidString ?? UUID().uuidString)-\(m.filename ?? "asset")"
    }

    static func taskDTO(from m: LillistTask) -> ExportSchema.TaskDTO {
        let tagIDs = ((m.tags as? Set<Tag>) ?? [])
            .compactMap(\.id)
            .sorted(by: { $0.uuidString < $1.uuidString })
        return ExportSchema.TaskDTO(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: Int(m.statusRaw),
            start: m.start,
            startHasTime: m.startHasTime,
            deadline: m.deadline,
            deadlineHasTime: m.deadlineHasTime,
            position: m.position,
            isPinned: m.isPinned,
            parentID: m.parent?.id,
            tagIDs: tagIDs,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt,
            closedAt: m.closedAt,
            deletedAt: m.deletedAt,
            schemaVersion: Int(m.schemaVersion),
            archivedAt: m.archivedAt,
            seriesID: m.series?.id
        )
    }

    /// X3: `Series` had zero export mapping before this plan.
    static func seriesDTO(from m: Series) -> ExportSchema.SeriesDTO {
        ExportSchema.SeriesDTO(
            id: m.id ?? UUID(),
            seedTaskID: m.seedTask?.id,
            rule: m.rule,
            nextOccurrenceAfter: m.nextOccurrenceAfter
        )
    }

    /// X3: `NotificationSpec` had zero export mapping before this plan.
    static func notificationSpecDTO(from m: NotificationSpec) -> ExportSchema.NotificationSpecDTO {
        ExportSchema.NotificationSpecDTO(
            id: m.id ?? UUID(),
            taskID: m.task?.id,
            kind: Int(m.kindRaw),
            offsetMinutes: m.offsetMinutes?.int32Value,
            fireDate: m.fireDate,
            lastFiredAt: m.lastFiredAt,
            snoozedUntil: m.snoozedUntil,
            createdAt: m.createdAt
        )
    }

    /// `SmartFilter` had zero export mapping before this plan (discovered via
    /// the model-derived completeness test). `predicateGroupJSON` decodes
    /// leniently — `nil` on missing/malformed JSON — matching
    /// `Series.rule`'s existing resilience pattern rather than throwing and
    /// losing the rest of the row.
    static func smartFilterDTO(from m: SmartFilter) -> ExportSchema.SmartFilterDTO {
        let group = m.predicateGroupJSON.flatMap { try? SmartFilterStore.decode($0) }
        return ExportSchema.SmartFilterDTO(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            predicateGroup: group,
            tintColor: m.tintColor,
            sortField: m.sortFieldRaw ?? SortField.deadline.rawValue,
            sortAscending: m.sortAscending,
            isPinned: m.isPinned,
            position: m.position,
            createdAt: m.createdAt,
            modifiedAt: m.modifiedAt
        )
    }

    static func tagDTO(from m: Tag) -> ExportSchema.TagDTO {
        ExportSchema.TagDTO(
            id: m.id ?? UUID(),
            name: m.name ?? "",
            tintColor: m.tintColor,
            parentID: m.parent?.id,
            position: m.position
        )
    }

    static func journalEntryDTO(from m: JournalEntry) -> ExportSchema.JournalEntryDTO {
        ExportSchema.JournalEntryDTO(
            id: m.id ?? UUID(),
            taskID: m.task?.id,
            kind: Int(m.kindRaw),
            body: m.body ?? "",
            payload: m.payload,
            createdAt: m.createdAt,
            editedAt: m.editedAt
        )
    }

    /// Project an attachment into its DTO plus, when it carries binary data, the
    /// bytes to write under `assets/<filename>`. `dto.dataPath` is
    /// `"assets/<filename>"` when bytes are present, `nil` otherwise (link
    /// previews carry no blob). The bytes are read here, inside `perform`; the
    /// caller writes them to disk *outside* the context queue.
    static func attachmentDTO(from m: Attachment) -> (dto: ExportSchema.AttachmentDTO, asset: (filename: String, bytes: Data)?) {
        if let data = m.data {
            let filename = assetFilename(for: m)
            let dto = ExportSchema.AttachmentDTO(
                id: m.id ?? UUID(),
                taskID: m.task?.id,
                journalEntryID: m.journalEntry?.id,
                kind: Int(m.kindRaw),
                filename: m.filename ?? "",
                uti: m.uti ?? "",
                byteSize: m.byteSize,
                dataPath: "assets/\(filename)",
                linkPreviewJSON: m.linkPreviewJSON,
                createdAt: m.createdAt
            )
            return (dto, (filename, data))
        }
        let dto = ExportSchema.AttachmentDTO(
            id: m.id ?? UUID(),
            taskID: m.task?.id,
            journalEntryID: m.journalEntry?.id,
            kind: Int(m.kindRaw),
            filename: m.filename ?? "",
            uti: m.uti ?? "",
            byteSize: m.byteSize,
            dataPath: nil,
            linkPreviewJSON: m.linkPreviewJSON,
            createdAt: m.createdAt
        )
        return (dto, nil)
    }

    /// Project the `AppPreferences` singleton row directly — not via
    /// `PreferencesStore.Prefs` — so callers can fetch it from their own
    /// background context inside their own `ctx.perform` block (X18: a
    /// separate `PreferencesStore.read()` round trip, on a different
    /// context, is exactly the kind of un-synchronized read this finding is
    /// about). Device-local fields Plan 21 partitioned into
    /// `DevicePreferencesStore` (`crashPromptsEnabled`,
    /// `hasCompletedOnboarding`, `quickCaptureEnabled`, `quickCaptureHotkey`,
    /// `statusBarItemVisible`) are deliberately excluded — see
    /// `ExportSchema.PreferencesDTO.defaultTagTintHex`'s doc comment.
    static func preferencesDTO(from m: AppPreferences) -> ExportSchema.PreferencesDTO {
        ExportSchema.PreferencesDTO(
            defaultAllDayHour: m.defaultAllDayNotificationHour,
            defaultAllDayMinute: m.defaultAllDayNotificationMinute,
            morningSummaryEnabled: m.morningSummaryEnabled,
            morningSummaryHour: m.morningSummaryHour,
            morningSummaryMinute: m.morningSummaryMinute,
            trashRetentionDays: m.trashRetentionDays,
            defaultTaskListSort: m.defaultTaskListSortRaw ?? SortField.manualPosition.rawValue,
            defaultTagTintHex: m.defaultTagTintHex ?? "#7F8FA6"
        )
    }
}
