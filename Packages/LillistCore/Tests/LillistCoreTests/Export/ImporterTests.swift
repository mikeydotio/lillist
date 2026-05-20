import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Importer")
struct ImporterTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Export the source store to a temp dir and return the path to the
    /// directory so an Importer can read it back.
    private func exportFixture(from p: PersistenceController) async throws -> URL {
        let prefs = PreferencesStore(persistence: p)
        _ = try await prefs.read()
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        try await exporter.export(to: dir)
        return dir
    }

    @Test("Import into empty store inserts all rows")
    func emptyStoreInserts() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        let srcTags = TagStore(persistence: src)
        let tag = try await srcTags.create(name: "Work", tintColor: "#FF0000")
        let task = try await srcTasks.create(title: "Ship")
        try await srcTasks.assignTag(taskID: task, tagID: tag)
        let bundle = try await exportFixture(from: src)

        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
        #expect(summary.tasksInserted == 1)
        #expect(summary.tagsInserted == 1)
        #expect(summary.tasksSkipped == 0)
        #expect(summary.errors.isEmpty)
    }

    @Test(".skipExisting leaves duplicates alone but inserts new rows")
    func skipExisting() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        let preExistingID = try await srcTasks.create(title: "Original")
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        // Seed dst with a row at the same ID and a different title to
        // prove `.skipExisting` won't overwrite it.
        let ctx = dst.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = preExistingID
            row.title = "Local edits — do not overwrite"
            row.statusRaw = 0
            row.position = 1
            row.createdAt = Date(timeIntervalSince1970: 100)
            try ctx.save()
        }
        // Add another row to the source so we can verify NEW rows
        // still come through.
        _ = try await srcTasks.create(title: "Brand new")
        let bundle = try await exportFixture(from: src)

        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
        #expect(summary.tasksInserted == 1)
        #expect(summary.tasksSkipped == 1)

        // Verify the local task is still "Local edits — do not overwrite".
        let preserved = try await fetchTitle(in: dst, id: preExistingID)
        _ = dstTasks
        #expect(preserved == "Local edits — do not overwrite")
    }

    @Test(".replaceExisting overwrites duplicates by UUID")
    func replaceExisting() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        let id = try await srcTasks.create(title: "Source title")
        let dst = try await TestStore.make()
        let ctx = dst.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = id
            row.title = "Old destination title"
            row.statusRaw = 0
            row.position = 1
            row.createdAt = Date()
            try ctx.save()
        }
        let bundle = try await exportFixture(from: src)
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .replaceExisting)
        #expect(summary.tasksUpdated == 1)
        #expect(summary.tasksInserted == 0)
        let after = try await fetchTitle(in: dst, id: id)
        #expect(after == "Source title")
    }

    @Test(".recencyWins keeps the newest by modifiedAt")
    func recencyWins() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        let id = try await srcTasks.create(title: "Newer source")
        // Stamp the source row's modifiedAt to a known future moment.
        let srcCtx = src.container.viewContext
        try await srcCtx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let row = try srcCtx.fetch(req).first {
                row.modifiedAt = Date(timeIntervalSince1970: 2_000_000_000)
                try srcCtx.save()
            }
        }
        let dst = try await TestStore.make()
        let dstCtx = dst.container.viewContext
        try await dstCtx.perform {
            let row = LillistTask(context: dstCtx)
            row.id = id
            row.title = "Older destination"
            row.statusRaw = 0
            row.position = 1
            row.createdAt = Date()
            row.modifiedAt = Date(timeIntervalSince1970: 1_000_000_000)
            try dstCtx.save()
        }
        let bundle = try await exportFixture(from: src)
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .recencyWins)
        #expect(summary.tasksUpdated == 1)
        let after = try await fetchTitle(in: dst, id: id)
        #expect(after == "Newer source")
    }

    @Test("Invalid bundle path throws")
    func invalidBundle() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        do {
            _ = try await importer.importBundle(
                at: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)"),
                conflictPolicy: .skipExisting
            )
            Issue.record("expected a thrown error")
        } catch {
            // Expected.
        }
    }
}

private extension LillistTask {
    var titleSnapshot: String { title ?? "" }
}

/// Tiny helper to fetch a LillistTask by id directly against a
/// known PersistenceController.
private func fetchTitle(in p: PersistenceController, id: UUID) async throws -> String? {
    let ctx = p.container.viewContext
    return try await ctx.perform {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try ctx.fetch(req).first?.title
    }
}
