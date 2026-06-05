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

    @Test("Import leaves the main viewContext with no stranded pending changes")
    func importDoesNotStrandViewContext() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        _ = try await srcTasks.create(title: "One")
        _ = try await srcTasks.create(title: "Two")
        let bundle = try await exportFixture(from: src)

        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
        #expect(summary.tasksInserted == 2)

        let viewHasChanges: Bool = await dst.container.viewContext.perform {
            dst.container.viewContext.hasChanges
        }
        #expect(viewHasChanges == false)

        let count: Int = try await dst.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try dst.container.viewContext.count(for: req)
        }
        #expect(count == 2)
    }

    /// Build a minimal, valid-shaped Document at an arbitrary schema
    /// version with no rows, so version-guard behavior can be tested in
    /// isolation from row-merge logic.
    private func emptyDocument(version: Int) -> ExportSchema.Document {
        ExportSchema.Document(
            version: version,
            exportedAt: Date(timeIntervalSince1970: 0),
            tasks: [],
            tags: [],
            journalEntries: [],
            attachments: [],
            preferences: ExportSchema.PreferencesDTO(
                defaultAllDayHour: 9,
                defaultAllDayMinute: 0,
                morningSummaryEnabled: false,
                morningSummaryHour: 8,
                morningSummaryMinute: 0,
                trashRetentionDays: 30,
                defaultTaskListSort: "manual"
            )
        )
    }

    @Test("Document at the current schema version applies")
    func versionEqualApplies() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.apply(
            document: emptyDocument(version: ExportSchema.version),
            policy: .skipExisting
        )
        #expect(summary.errors.isEmpty)
    }

    @Test("Document at an older schema version applies (forward upgrade)")
    func versionOlderApplies() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        // ExportSchema.version is 1 today; version 0 stands in for an
        // older bundle. If/when version climbs this stays a down-level case.
        let summary = try await importer.apply(
            document: emptyDocument(version: ExportSchema.version - 1),
            policy: .skipExisting
        )
        #expect(summary.errors.isEmpty)
    }

    @Test("Document at a newer schema version throws unsupportedExportVersion")
    func versionNewerThrows() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        do {
            _ = try await importer.apply(
                document: emptyDocument(version: ExportSchema.version + 1),
                policy: .skipExisting
            )
            Issue.record("expected unsupportedExportVersion to be thrown")
        } catch let error as LillistError {
            #expect(error == .unsupportedExportVersion(
                found: ExportSchema.version + 1,
                supported: ExportSchema.version
            ))
        }
    }

    @Test("Journal entry with nil taskID is skipped and recorded")
    func nilTaskIDJournalEntrySkipped() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        var doc = emptyDocument(version: ExportSchema.version)
        let orphanID = UUID()
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: orphanID,
                taskID: nil,
                kind: JournalEntryKind.note.rawValue,
                body: "no owner",
                payload: nil,
                createdAt: Date(timeIntervalSince1970: 1),
                editedAt: nil
            )
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.journalEntriesInserted == 0)
        #expect(summary.journalEntriesSkipped == 1)
        #expect(summary.errors.count == 1)
        #expect(summary.errors[0].contains(orphanID.uuidString))
    }

    @Test("Journal entry referencing an absent task is skipped and recorded")
    func unresolvedTaskIDJournalEntrySkipped() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        var doc = emptyDocument(version: ExportSchema.version)
        let entryID = UUID()
        let danglingTaskID = UUID() // never appears in doc.tasks or the store
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: entryID,
                taskID: danglingTaskID,
                kind: JournalEntryKind.note.rawValue,
                body: "owner missing",
                payload: nil,
                createdAt: Date(timeIntervalSince1970: 2),
                editedAt: nil
            )
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.journalEntriesInserted == 0)
        #expect(summary.journalEntriesSkipped == 1)
        #expect(summary.errors.count == 1)
        #expect(summary.errors[0].contains(entryID.uuidString))
    }

    @Test("Truncated lillist.json throws a decoding error and persists nothing")
    func truncatedJSONThrows() async throws {
        // Produce a real, valid bundle then corrupt lillist.json by
        // chopping it mid-object so the decoder must fail.
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        _ = try await srcTasks.create(title: "Will be truncated")
        let bundle = try await exportFixture(from: src)

        let docURL = bundle.appendingPathComponent("lillist.json")
        let full = try Data(contentsOf: docURL)
        // Keep the opening brace + first ~12 bytes: structurally invalid JSON.
        let truncated = full.prefix(12)
        try truncated.write(to: docURL)

        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        do {
            _ = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
            Issue.record("expected a decoding error on truncated JSON")
        } catch is DecodingError {
            // Expected: JSONDecoder.decode throws DecodingError.
        } catch {
            Issue.record("expected DecodingError, got \(error)")
        }

        // The destination store must be untouched.
        let count = try await taskCount(in: dst)
        #expect(count == 0)
    }

    @Test("A catchable save failure can be rolled back to the pre-edit baseline (transaction-contract mechanism)")
    func saveFailureRollbackIsCatchable() async throws {
        // The only save() that throws a CATCHABLE Swift error on this
        // permissive CloudKit model is an optimistic-lock merge conflict
        // under NSMergePolicy.error (a nil id, a missing attribute, etc.
        // all save fine; KVC type-violations raise an NSException that
        // crashes the process). We reproduce that mechanism on two
        // background contexts we fully control, then prove rollback
        // restores the baseline — the rollback half of the import's
        // all-or-nothing contract.
        let p = try await TestStore.make()
        let id = UUID()

        // Seed a committed row through the view context.
        let main = p.container.viewContext
        await main.perform {
            let t = LillistTask(context: main)
            t.id = id
            t.title = "baseline"
            try? main.save()
        }

        let c1 = p.container.newBackgroundContext(); c1.mergePolicy = NSMergePolicy.error
        let c2 = p.container.newBackgroundContext(); c2.mergePolicy = NSMergePolicy.error

        // Both contexts mutate the same row off the same snapshot.
        await c1.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? c1.fetch(req).first)?.title = "edit-1"
        }
        await c2.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? c2.fetch(req).first)?.title = "edit-2"
        }

        // First save wins; second save is now stale and throws a
        // catchable NSError (NSManagedObjectMergeError).
        let firstThrew: Bool = await c1.perform {
            do { try c1.save(); return false } catch { return true }
        }
        let secondThrew: Bool = await c2.perform {
            do { try c2.save(); return false } catch { return true }
        }
        #expect(firstThrew == false)
        #expect(secondThrew == true)

        // Rolling back the failed context drops its pending edit; the
        // committed store value (from c1) is what survives.
        await c2.perform { c2.rollback() }
        let after = try await fetchTitle(in: p, id: id)
        #expect(after == "edit-1")
    }

    @Test("A successful import commits every row in one transaction — no partial subset (transaction contract)")
    func importIsSingleAtomicSave() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)

        // A multi-row bundle: 2 tags, 3 tasks, 2 journal entries owned by
        // those tasks. A single ctx.save() commits all of them together —
        // Core Data cannot persist a strict subset of one transaction.
        var doc = emptyDocument(version: ExportSchema.version)
        let tagA = UUID(), tagB = UUID()
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        doc.tags = [
            ExportSchema.TagDTO(id: tagA, name: "Work", tintColor: "#FF0000", parentID: nil, position: 0),
            ExportSchema.TagDTO(id: tagB, name: "Home", tintColor: "#00FF00", parentID: nil, position: 1)
        ]
        func task(_ id: UUID, _ title: String, _ pos: Double, tags: [UUID]) -> ExportSchema.TaskDTO {
            ExportSchema.TaskDTO(
                id: id, title: title, notes: "", status: 0,
                start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
                position: pos, isPinned: false, parentID: nil, tagIDs: tags,
                createdAt: Date(timeIntervalSince1970: pos), modifiedAt: nil,
                closedAt: nil, deletedAt: nil
            )
        }
        doc.tasks = [
            task(t1, "Alpha", 0, tags: [tagA]),
            task(t2, "Beta", 1, tags: [tagB]),
            task(t3, "Gamma", 2, tags: [])
        ]
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: UUID(), taskID: t1, kind: JournalEntryKind.note.rawValue,
                body: "note on alpha", payload: nil,
                createdAt: Date(timeIntervalSince1970: 5), editedAt: nil
            ),
            ExportSchema.JournalEntryDTO(
                id: UUID(), taskID: t2, kind: JournalEntryKind.note.rawValue,
                body: "note on beta", payload: nil,
                createdAt: Date(timeIntervalSince1970: 6), editedAt: nil
            )
        ]

        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksInserted == 3)
        #expect(summary.tagsInserted == 2)
        #expect(summary.journalEntriesInserted == 2)
        #expect(summary.errors.isEmpty)

        // The whole batch is visible in the store — all-or-nothing's
        // "all" half: a single save() committed every staged row.
        #expect(try await taskCount(in: dst) == 3)
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

/// Count LillistTask rows in a store — used to prove all-or-nothing
/// import semantics.
private func taskCount(in p: PersistenceController) async throws -> Int {
    let ctx = p.container.viewContext
    return try await ctx.perform {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        return try ctx.count(for: req)
    }
}
