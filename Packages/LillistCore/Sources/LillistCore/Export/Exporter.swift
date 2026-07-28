import Foundation
import CoreData

public final class Exporter: @unchecked Sendable {
    private let persistence: PersistenceController
    /// Kept for API compatibility with existing call sites (both apps, the
    /// CLI, and the test suite construct `Exporter` with this parameter).
    /// No longer read from directly: `buildDocument` fetches `AppPreferences`
    /// straight from its own background context by `PreferencesStore
    /// .singletonID` instead of going through `PreferencesStore.read()`,
    /// which used a *separate* context/round trip and was a live instance
    /// of X18's exact defect (a torn read between preferences and every
    /// other fetch).
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

        // Attachment bytes are read into value types INSIDE perform (via the
        // shared `BackupRecordProjector`); the files themselves are written to
        // disk OUTSIDE perform so no file I/O happens while holding the Core
        // Data context queue.
        struct PendingAsset {
            let filename: String
            let bytes: Data
        }

        // X18: every fetch this export needs — including AppPreferences,
        // which used to be read via a *separate* PreferencesStore.read()
        // round trip on a different context before this block even started
        // — lives inside this one ctx.perform block, so a concurrent write
        // landing mid-export can't tear the bundle between data sources.
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

            // X3: recurrence series, reminders, and saved smart filters —
            // previously entirely absent from the export.
            let seriesReq = NSFetchRequest<Series>(entityName: "Series")
            let seriesDTOs = try ctx.fetch(seriesReq).map(BackupRecordProjector.seriesDTO(from:))

            let specReq = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            let specDTOs = try ctx.fetch(specReq).map(BackupRecordProjector.notificationSpecDTO(from:))

            let filterReq = NSFetchRequest<SmartFilter>(entityName: "SmartFilter")
            let filterDTOs = try ctx.fetch(filterReq).map(BackupRecordProjector.smartFilterDTO(from:))

            // X18: fetched from this same ctx/perform, by the well-known
            // singleton id, instead of PreferencesStore.read() (view
            // context, separate round trip). An absent row (a store that
            // was never touched) falls back to the model's own defaults.
            let prefsReq = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            prefsReq.predicate = NSPredicate(format: "id == %@", PreferencesStore.singletonID as CVarArg)
            prefsReq.fetchLimit = 1
            let prefsRow = try ctx.fetch(prefsReq).first
            let prefsDTO = prefsRow.map(BackupRecordProjector.preferencesDTO(from:)) ?? .fallback

            let doc = ExportSchema.Document(
                version: ExportSchema.version,
                exportedAt: Date(),
                tasks: taskDTOs,
                tags: tagDTOs,
                journalEntries: journalDTOs,
                attachments: attDTOs,
                preferences: prefsDTO,
                series: seriesDTOs,
                notificationSpecs: specDTOs,
                smartFilters: filterDTOs
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
