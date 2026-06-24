import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Wave 0 — the per-task CloudKit schema version (issue #7). Proves every
/// local write stamps `CloudKitSchema.currentVersion`, that the value rides
/// through the export/import DTO boundary, and that bundles predating the
/// field decode cleanly as `0`.
@Suite("Backup schema version")
struct BackupSchemaVersionTests {
    /// Read a task's persisted `schemaVersion` off the view context.
    /// Returns `-1` if the task is missing.
    private func schemaVersion(of id: UUID, in p: PersistenceController) async throws -> Int {
        let ctx = p.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            guard let m = try ctx.fetch(req).first else { return -1 }
            return Int(m.schemaVersion)
        }
    }

    @Test("create stamps the current schema version")
    func createStamps() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Stamped")
        #expect(try await schemaVersion(of: id, in: p) == CloudKitSchema.currentVersion)
    }

    @Test("update and transition keep the current schema version")
    func mutationsRestamp() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Mutate me")
        try await tasks.update(id: id) { $0.notes = "edited" }
        #expect(try await schemaVersion(of: id, in: p) == CloudKitSchema.currentVersion)
        try await tasks.transition(id: id, to: .closed)
        #expect(try await schemaVersion(of: id, in: p) == CloudKitSchema.currentVersion)
    }

    @Test("soft delete stamps the schema version on the trashed row")
    func softDeleteStamps() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let id = try await tasks.create(title: "Trash me")
        try await tasks.softDelete(id: id)
        #expect(try await schemaVersion(of: id, in: p) == CloudKitSchema.currentVersion)
    }

    @Test("Exporter serializes the task's schema version")
    func exporterSerializes() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)
        _ = try await tasks.create(title: "Ship")

        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-schemaver-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
        #expect(doc.tasks.count == 1)
        #expect(doc.tasks[0].schemaVersion == CloudKitSchema.currentVersion)
    }

    @Test("TaskDTO from a pre-versioning bundle decodes schemaVersion as 0")
    func defaultSafeDecode() async throws {
        // A v1 bundle predates `schemaVersion`, so the key is absent. The
        // custom decoder must default it to 0 rather than throw keyNotFound.
        let json = Data("""
        {"id":"\(UUID().uuidString)","title":"Legacy","notes":"","status":0,\
        "startHasTime":false,"deadlineHasTime":false,"position":1.0,\
        "isPinned":false,"tagIDs":[]}
        """.utf8)
        let dto = try JSONDecoder().decode(ExportSchema.TaskDTO.self, from: json)
        #expect(dto.schemaVersion == 0)
        #expect(dto.title == "Legacy")
    }

    @Test("TaskDTO round-trips schemaVersion through encode/decode")
    func encodeDecodeRoundTrip() async throws {
        let dto = ExportSchema.TaskDTO(
            id: UUID(), title: "RT", notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1, isPinned: false, parentID: nil, tagIDs: [],
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil,
            schemaVersion: 7
        )
        let data = try JSONEncoder().encode(dto)
        let back = try JSONDecoder().decode(ExportSchema.TaskDTO.self, from: data)
        #expect(back.schemaVersion == 7)
    }

    @Test("Importer stamps imported rows with the current schema version")
    func importerStampsCurrent() async throws {
        let p = try await TestStore.make()
        let importer = Importer(persistence: p)
        let taskID = UUID()
        // schemaVersion omitted (defaults to 0) — the importer must override it
        // to current because the row is written with this build's field shape.
        let dto = ExportSchema.TaskDTO(
            id: taskID, title: "Imported", notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1, isPinned: false, parentID: nil, tagIDs: [],
            createdAt: Date(), modifiedAt: Date(), closedAt: nil, deletedAt: nil
        )
        let doc = ExportSchema.Document(
            version: ExportSchema.version,
            exportedAt: Date(),
            tasks: [dto],
            tags: [],
            journalEntries: [],
            attachments: [],
            preferences: ExportSchema.PreferencesDTO(
                defaultAllDayHour: 9, defaultAllDayMinute: 0,
                morningSummaryEnabled: true, morningSummaryHour: 9,
                morningSummaryMinute: 0, trashRetentionDays: 30,
                defaultTaskListSort: "manualPosition"
            )
        )
        _ = try await importer.apply(document: doc, policy: .replaceExisting)
        #expect(try await schemaVersion(of: taskID, in: p) == CloudKitSchema.currentVersion)
    }
}
