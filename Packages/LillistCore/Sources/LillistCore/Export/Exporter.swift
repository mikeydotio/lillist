import Foundation
import CoreData

public final class Exporter: @unchecked Sendable {
    private let persistence: PersistenceController
    private let preferences: PreferencesStore

    public init(persistence: PersistenceController, preferences: PreferencesStore) {
        self.persistence = persistence
        self.preferences = preferences
    }

    /// Writes `lillist.json` and an `assets/` folder under `dir`.
    /// `dir` must exist and be empty.
    public func export(to dir: URL) async throws {
        try ensureEmptyDirectory(dir)
        let assetsDir = dir.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        let document = try await buildDocument(assetsDir: assetsDir)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(document)
        try data.write(to: dir.appendingPathComponent("lillist.json"))
    }

    private func ensureEmptyDirectory(_ dir: URL) throws {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        if !contents.isEmpty {
            throw LillistError.validationFailed([
                .init(field: "exportDir", message: "must be empty")
            ])
        }
    }

    private func buildDocument(assetsDir: URL) async throws -> ExportSchema.Document {
        let ctx = persistence.container.viewContext
        let prefs = try await preferences.read()

        return try await ctx.perform {
            // Tasks (including trashed — full backup)
            let taskReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            taskReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let taskMOs = try ctx.fetch(taskReq)
            let taskDTOs = taskMOs.map { m -> ExportSchema.TaskDTO in
                let tagIDs = ((m.tags as? Set<Tag>) ?? []).compactMap(\.id).sorted(by: { $0.uuidString < $1.uuidString })
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
                    deletedAt: m.deletedAt
                )
            }

            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            let tagDTOs = try ctx.fetch(tagReq).map { m in
                ExportSchema.TagDTO(
                    id: m.id ?? UUID(),
                    name: m.name ?? "",
                    tintColor: m.tintColor,
                    parentID: m.parent?.id,
                    position: m.position
                )
            }

            let journalReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            journalReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let journalDTOs = try ctx.fetch(journalReq).map { m in
                ExportSchema.JournalEntryDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    kind: Int(m.kindRaw),
                    body: m.body ?? "",
                    payload: m.payload,
                    createdAt: m.createdAt,
                    editedAt: m.editedAt
                )
            }

            let attReq = NSFetchRequest<Attachment>(entityName: "Attachment")
            let attDTOs = try ctx.fetch(attReq).map { m -> ExportSchema.AttachmentDTO in
                var path: String?
                if let data = m.data {
                    let filename = "\(m.id?.uuidString ?? UUID().uuidString)-\(m.filename ?? "asset")"
                    let url = assetsDir.appendingPathComponent(filename)
                    try? data.write(to: url)
                    path = "assets/\(filename)"
                }
                return ExportSchema.AttachmentDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    journalEntryID: m.journalEntry?.id,
                    kind: Int(m.kindRaw),
                    filename: m.filename ?? "",
                    uti: m.uti ?? "",
                    byteSize: m.byteSize,
                    dataPath: path,
                    linkPreviewJSON: m.linkPreviewJSON,
                    createdAt: m.createdAt
                )
            }

            let prefsDTO = ExportSchema.PreferencesDTO(
                defaultAllDayHour: prefs.defaultAllDayHour,
                defaultAllDayMinute: prefs.defaultAllDayMinute,
                morningSummaryEnabled: prefs.morningSummaryEnabled,
                morningSummaryHour: prefs.morningSummaryHour,
                morningSummaryMinute: prefs.morningSummaryMinute,
                trashRetentionDays: prefs.trashRetentionDays,
                defaultTaskListSort: prefs.defaultTaskListSort.rawValue
            )

            return ExportSchema.Document(
                version: ExportSchema.version,
                exportedAt: Date(),
                tasks: taskDTOs,
                tags: tagDTOs,
                journalEntries: journalDTOs,
                attachments: attDTOs,
                preferences: prefsDTO
            )
        }
    }
}
