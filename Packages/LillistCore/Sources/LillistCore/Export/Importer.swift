import Foundation
import CoreData

/// Reads an `ExportSchema.Document` produced by `Exporter` and writes
/// the contained tasks, tags, and journal entries back into Core Data.
///
/// Plan 21 Wave 7: provides the manual merge escape hatch the
/// destructive sync-mode change deliberately skips. The importer
/// supports three conflict policies:
///
/// - `.skipExisting` — UUIDs already in the store are left alone.
/// - `.replaceExisting` — UUIDs already in the store are overwritten.
/// - `.recencyWins` — uses `modifiedAt` (falling back to `createdAt`)
///   to pick a winner per row.
///
/// Attachments are not imported in this revision — the JSON+assets
/// bundle's `assets/` folder is referenced but copy-back lands in a
/// later patch alongside the iOS document picker affordance.
public actor Importer {
    public let persistence: PersistenceController

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public enum ConflictPolicy: Sendable, Equatable {
        case skipExisting
        case replaceExisting
        case recencyWins
    }

    public struct ImportSummary: Sendable, Equatable {
        public let tasksInserted: Int
        public let tasksUpdated: Int
        public let tasksSkipped: Int
        public let tagsInserted: Int
        public let tagsUpdated: Int
        public let tagsSkipped: Int
        public let journalEntriesInserted: Int
        public let journalEntriesUpdated: Int
        public let journalEntriesSkipped: Int
        public let errors: [String]

        public init(
            tasksInserted: Int = 0,
            tasksUpdated: Int = 0,
            tasksSkipped: Int = 0,
            tagsInserted: Int = 0,
            tagsUpdated: Int = 0,
            tagsSkipped: Int = 0,
            journalEntriesInserted: Int = 0,
            journalEntriesUpdated: Int = 0,
            journalEntriesSkipped: Int = 0,
            errors: [String] = []
        ) {
            self.tasksInserted = tasksInserted
            self.tasksUpdated = tasksUpdated
            self.tasksSkipped = tasksSkipped
            self.tagsInserted = tagsInserted
            self.tagsUpdated = tagsUpdated
            self.tagsSkipped = tagsSkipped
            self.journalEntriesInserted = journalEntriesInserted
            self.journalEntriesUpdated = journalEntriesUpdated
            self.journalEntriesSkipped = journalEntriesSkipped
            self.errors = errors
        }
    }

    /// Import a previously-exported bundle at `bundleURL`. The bundle
    /// is expected to be the directory the Exporter writes — with
    /// `lillist.json` at the top level.
    public func importBundle(at bundleURL: URL, conflictPolicy: ConflictPolicy) async throws -> ImportSummary {
        let docURL = bundleURL.appendingPathComponent("lillist.json")
        let data = try Data(contentsOf: docURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportSchema.Document.self, from: data)
        return try await apply(document: document, policy: conflictPolicy)
    }

    public func apply(document: ExportSchema.Document, policy: ConflictPolicy) async throws -> ImportSummary {
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [policy, self] in
            var tagsInserted = 0
            var tagsUpdated = 0
            var tagsSkipped = 0
            var tasksInserted = 0
            var tasksUpdated = 0
            var tasksSkipped = 0
            var entriesInserted = 0
            var entriesUpdated = 0
            var entriesSkipped = 0
            var errors: [String] = []

            var tagByID: [UUID: Tag] = [:]
            for dto in document.tags {
                do {
                    if let existing = try self.fetchTag(id: dto.id, ctx: ctx) {
                        switch policy {
                        case .skipExisting:
                            tagsSkipped += 1
                        case .replaceExisting:
                            self.applyTag(dto, into: existing)
                            tagsUpdated += 1
                        case .recencyWins:
                            // Tags don't carry modifiedAt yet; fall back
                            // to "incoming wins" so multi-device imports
                            // converge predictably.
                            self.applyTag(dto, into: existing)
                            tagsUpdated += 1
                        }
                        tagByID[dto.id] = existing
                    } else {
                        let row = Tag(context: ctx)
                        row.id = dto.id
                        self.applyTag(dto, into: row)
                        tagsInserted += 1
                        tagByID[dto.id] = row
                    }
                } catch {
                    errors.append("tag \(dto.id): \(error.localizedDescription)")
                }
            }
            // Second pass to wire tag.parent (now that all rows exist).
            for dto in document.tags {
                guard let row = tagByID[dto.id], let parentID = dto.parentID else { continue }
                row.parent = tagByID[parentID]
            }

            var taskByID: [UUID: LillistTask] = [:]
            for dto in document.tasks {
                do {
                    if let existing = try self.fetchTask(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.modifiedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.modifiedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            tasksSkipped += 1
                        case .update:
                            self.applyTask(dto, into: existing, tagByID: tagByID)
                            tasksUpdated += 1
                        }
                        taskByID[dto.id] = existing
                    } else {
                        let row = LillistTask(context: ctx)
                        row.id = dto.id
                        self.applyTask(dto, into: row, tagByID: tagByID)
                        tasksInserted += 1
                        taskByID[dto.id] = row
                    }
                } catch {
                    errors.append("task \(dto.id): \(error.localizedDescription)")
                }
            }
            for dto in document.tasks {
                guard let row = taskByID[dto.id], let parentID = dto.parentID else { continue }
                row.parent = taskByID[parentID]
            }

            for dto in document.journalEntries {
                do {
                    if let existing = try self.fetchJournalEntry(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.editedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.editedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            entriesSkipped += 1
                        case .update:
                            self.applyEntry(dto, into: existing, taskByID: taskByID)
                            entriesUpdated += 1
                        }
                    } else {
                        let row = JournalEntry(context: ctx)
                        row.id = dto.id
                        self.applyEntry(dto, into: row, taskByID: taskByID)
                        entriesInserted += 1
                    }
                } catch {
                    errors.append("journalEntry \(dto.id): \(error.localizedDescription)")
                }
            }

            try ctx.save()
            return ImportSummary(
                tasksInserted: tasksInserted,
                tasksUpdated: tasksUpdated,
                tasksSkipped: tasksSkipped,
                tagsInserted: tagsInserted,
                tagsUpdated: tagsUpdated,
                tagsSkipped: tagsSkipped,
                journalEntriesInserted: entriesInserted,
                journalEntriesUpdated: entriesUpdated,
                journalEntriesSkipped: entriesSkipped,
                errors: errors
            )
        }
    }

    private enum Action { case skip, update }
    private nonisolated func decideAction(
        policy: ConflictPolicy,
        existingModified: Date?,
        existingCreated: Date?,
        incomingModified: Date?,
        incomingCreated: Date?
    ) -> Action {
        switch policy {
        case .skipExisting:
            return .skip
        case .replaceExisting:
            return .update
        case .recencyWins:
            let existing = existingModified ?? existingCreated ?? .distantPast
            let incoming = incomingModified ?? incomingCreated ?? .distantPast
            return incoming > existing ? .update : .skip
        }
    }

    // MARK: - Apply helpers (nonisolated; only touch Core Data via ctx)

    private nonisolated func applyTag(_ dto: ExportSchema.TagDTO, into row: Tag) {
        row.name = dto.name
        row.tintColor = dto.tintColor
        row.position = dto.position
    }

    private nonisolated func applyTask(_ dto: ExportSchema.TaskDTO, into row: LillistTask, tagByID: [UUID: Tag]) {
        row.title = dto.title
        row.notes = dto.notes
        row.statusRaw = Int16(dto.status)
        row.start = dto.start
        row.startHasTime = dto.startHasTime
        row.deadline = dto.deadline
        row.deadlineHasTime = dto.deadlineHasTime
        row.position = dto.position
        row.isPinned = dto.isPinned
        row.createdAt = dto.createdAt
        row.modifiedAt = dto.modifiedAt
        row.closedAt = dto.closedAt
        row.deletedAt = dto.deletedAt
        let resolved = dto.tagIDs.compactMap { tagByID[$0] }
        row.tags = NSSet(array: resolved)
    }

    private nonisolated func applyEntry(_ dto: ExportSchema.JournalEntryDTO, into row: JournalEntry, taskByID: [UUID: LillistTask]) {
        row.task = taskByID[dto.taskID]
        row.kindRaw = Int16(dto.kind)
        row.body = dto.body
        row.payload = dto.payload
        row.createdAt = dto.createdAt
        row.editedAt = dto.editedAt
    }

    private nonisolated func fetchTag(id: UUID, ctx: NSManagedObjectContext) throws -> Tag? {
        let req = NSFetchRequest<Tag>(entityName: "Tag")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchTask(id: UUID, ctx: NSManagedObjectContext) throws -> LillistTask? {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }

    private nonisolated func fetchJournalEntry(id: UUID, ctx: NSManagedObjectContext) throws -> JournalEntry? {
        let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try ctx.fetch(req).first
    }
}
