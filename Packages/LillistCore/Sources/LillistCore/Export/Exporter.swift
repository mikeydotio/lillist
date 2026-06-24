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
        let ctx = persistence.makeBackgroundContext()
        let prefs = try await preferences.read()

        // Attachment bytes are read into value types INSIDE perform (via the
        // shared `BackupRecordProjector`); the files themselves are written to
        // disk OUTSIDE perform so no file I/O happens while holding the Core
        // Data context queue.
        struct PendingAsset {
            let filename: String
            let bytes: Data
        }

        let (document, pendingAssets): (ExportSchema.Document, [PendingAsset]) = try await ctx.perform {
            // Tasks (including trashed — full backup)
            let taskReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            taskReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let taskDTOs = try ctx.fetch(taskReq).map(BackupRecordProjector.taskDTO(from:))

            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            let tagDTOs = try ctx.fetch(tagReq).map(BackupRecordProjector.tagDTO(from:))

            let journalReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            journalReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let journalDTOs = try ctx.fetch(journalReq).map(BackupRecordProjector.journalEntryDTO(from:))

            let attReq = NSFetchRequest<Attachment>(entityName: "Attachment")
            var pending: [PendingAsset] = []
            let attDTOs = try ctx.fetch(attReq).map { m -> ExportSchema.AttachmentDTO in
                let projected = BackupRecordProjector.attachmentDTO(from: m)
                if let asset = projected.asset {
                    pending.append(PendingAsset(filename: asset.filename, bytes: asset.bytes))
                }
                return projected.dto
            }

            let prefsDTO = BackupRecordProjector.preferencesDTO(from: prefs)

            let doc = ExportSchema.Document(
                version: ExportSchema.version,
                exportedAt: Date(),
                tasks: taskDTOs,
                tags: tagDTOs,
                journalEntries: journalDTOs,
                attachments: attDTOs,
                preferences: prefsDTO
            )
            return (doc, pending)
        }

        // File I/O OUTSIDE the Core Data context queue.
        for asset in pendingAssets {
            let url = assetsDir.appendingPathComponent(asset.filename)
            try asset.bytes.write(to: url)
        }

        return document
    }
}
