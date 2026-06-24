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
            schemaVersion: Int(m.schemaVersion)
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

    /// Project the value-type `Prefs` into the export DTO subset.
    static func preferencesDTO(from prefs: PreferencesStore.Prefs) -> ExportSchema.PreferencesDTO {
        ExportSchema.PreferencesDTO(
            defaultAllDayHour: prefs.defaultAllDayHour,
            defaultAllDayMinute: prefs.defaultAllDayMinute,
            morningSummaryEnabled: prefs.morningSummaryEnabled,
            morningSummaryHour: prefs.morningSummaryHour,
            morningSummaryMinute: prefs.morningSummaryMinute,
            trashRetentionDays: prefs.trashRetentionDays,
            defaultTaskListSort: prefs.defaultTaskListSort.rawValue
        )
    }
}
