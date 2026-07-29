import Testing
import Foundation
import CoreData
@testable import LillistCore

/// X3 — Export/import/backup silently dropped `Series`, `NotificationSpec`,
/// and `archivedAt` (plus, discovered via the model-derived completeness
/// test, `SmartFilter` in its entirety and `AppPreferences
/// .defaultTagTintHex`). These tests prove the full round trip through
/// `Exporter`/`Importer` — the exact mechanism `resetAndReseedFromThisDevice`
/// and every backup restore depend on.
@Suite("X3 — export schema completeness (Series/NotificationSpec/SmartFilter/archivedAt/defaultTagTintHex)")
struct X3ExportSchemaCompletenessTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-x3-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Full round trip: archived task, recurrence series, reminder, smart filter, and account tag-tint preference all survive export -> import into a fresh store")
    func fullRoundTrip() async throws {
        let src = try await TestStore.make()
        let tasks = TaskStore(persistence: src)
        let series = SeriesStore(persistence: src)
        let specs = NotificationSpecStore(persistence: src)
        let filters = SmartFilterStore(persistence: src)
        let prefs = PreferencesStore(persistence: src)

        // Archived task (X3's own archivedAt).
        let archivedID = try await tasks.create(title: "Old chore")
        try await tasks.transition(id: archivedID, to: .closed)
        _ = try await tasks.archive(ids: [archivedID])

        // Recurrence series (X3's own Series/NotificationSpec — a seed task
        // recurring daily, with a reminder attached).
        let seedID = try await tasks.create(title: "Water plants")
        let seriesID = try await series.create(
            fromSeedTask: seedID,
            rule: .calendar(.init(freq: .daily, interval: 1))
        )
        let specID = try await specs.add(
            taskID: seedID, kind: .offsetDeadline, offsetMinutes: 30,
            fireDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
        // lastFiredAt is real CloudKit-synced cross-device de-dup state — it
        // must round-trip as-is (see ExportSchema.NotificationSpecDTO's doc
        // comment), not reset to nil on import.
        try await specs.recordLastFired(id: specID, at: Date(timeIntervalSince1970: 1_999_990_000))

        // Smart filter (discovered gap — had zero export mapping at all).
        let filterID = try await filters.create(
            name: "Overdue", group: .init(combinator: .all, predicates: []), tintColor: "#123456"
        )

        // Real, synced account preference that was silently dropped
        // (distinct from the five Plan-21 device-local fields).
        try await prefs.update { $0.defaultTagTintHex = "#ABCDEF" }

        let exporter = Exporter(persistence: src, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)

        // The raw JSON actually carries the new fields (not just "the
        // importer happens to reconstruct them some other way").
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
        #expect(doc.version == 2)
        #expect(doc.series.count == 1)
        #expect(doc.series[0].id == seriesID)
        #expect(doc.series[0].seedTaskID == seedID)
        #expect(doc.series[0].rule == .calendar(.init(freq: .daily, interval: 1)))
        #expect(doc.notificationSpecs.count == 1)
        #expect(doc.notificationSpecs[0].id == specID)
        #expect(doc.notificationSpecs[0].taskID == seedID)
        #expect(doc.notificationSpecs[0].lastFiredAt != nil)
        #expect(doc.smartFilters.count == 1)
        #expect(doc.smartFilters[0].id == filterID)
        #expect(doc.smartFilters[0].tintColor == "#123456")
        #expect(doc.preferences.defaultTagTintHex == "#ABCDEF")
        let archivedDTO = try #require(doc.tasks.first { $0.id == archivedID })
        #expect(archivedDTO.archivedAt != nil)
        let seedDTO = try #require(doc.tasks.first { $0.id == seedID })
        #expect(seedDTO.seriesID == seriesID)

        // Now import into a FRESH destination store and verify every one of
        // these survives — the actual failure mode X3 describes.
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: dir, conflictPolicy: .replaceExisting)
        #expect(summary.errors.isEmpty)
        #expect(summary.seriesInserted == 1)
        #expect(summary.notificationSpecsInserted == 1)
        #expect(summary.smartFiltersInserted == 1)

        let dstTasks = TaskStore(persistence: dst)
        let dstSeries = SeriesStore(persistence: dst)
        let dstSpecs = NotificationSpecStore(persistence: dst)
        let dstFilters = SmartFilterStore(persistence: dst)

        let restoredArchived = try await dstTasks.fetch(id: archivedID)
        #expect(restoredArchived.archivedAt != nil)

        let restoredSeed = try await dstTasks.fetch(id: seedID)
        #expect(restoredSeed.seriesID == seriesID)

        let restoredSeries = try await dstSeries.fetch(id: seriesID)
        #expect(restoredSeries.seedTaskID == seedID)
        #expect(restoredSeries.rule == .calendar(.init(freq: .daily, interval: 1)))
        let restoredInstances = try await dstSeries.instances(of: seriesID)
        #expect(restoredInstances == [seedID])

        let restoredSpec = try await dstSpecs.fetch(id: specID)
        #expect(restoredSpec.taskID == seedID)
        #expect(restoredSpec.offsetMinutes == 30)
        #expect(restoredSpec.lastFiredAt != nil, "lastFiredAt must round-trip, not reset")

        let restoredFilter = try await dstFilters.fetch(id: filterID)
        #expect(restoredFilter.name == "Overdue")
        #expect(restoredFilter.tintColor == "#123456")

        // Importer.apply deliberately never touches preferences (see its
        // doc comment) — that's BackupRestoreService.applyPreferences's job.
        // defaultTagTintHex round-tripping through a full restore (which
        // DOES apply preferences) is covered in BackupRestoreServiceTests.
    }

    @Test("A v1-shaped bundle (no series/notificationSpecs/smartFilters/archivedAt/seriesID/defaultTagTintHex keys) decodes with safe defaults")
    func v1BundleDecodesWithDefaults() throws {
        let taskID = UUID()
        let json = Data("""
        {
          "version": 1,
          "exportedAt": "2026-01-01T00:00:00Z",
          "tasks": [{
            "id": "\(taskID.uuidString)", "title": "Legacy", "notes": "", "status": 0,
            "startHasTime": false, "deadlineHasTime": false, "position": 1.0,
            "isPinned": false, "tagIDs": []
          }],
          "tags": [],
          "journalEntries": [],
          "attachments": [],
          "preferences": {
            "defaultAllDayHour": 9, "defaultAllDayMinute": 0,
            "morningSummaryEnabled": true, "morningSummaryHour": 9, "morningSummaryMinute": 0,
            "trashRetentionDays": 30, "defaultTaskListSort": "manualPosition"
          }
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(ExportSchema.Document.self, from: json)
        #expect(doc.series.isEmpty)
        #expect(doc.notificationSpecs.isEmpty)
        #expect(doc.smartFilters.isEmpty)
        #expect(doc.preferences.defaultTagTintHex == "#7F8FA6")
        #expect(doc.tasks[0].archivedAt == nil)
        #expect(doc.tasks[0].seriesID == nil)
    }

    @Test("A newer-version bundle carrying the new fields is still rejected by the version guard (unchanged forward-incompatibility mechanism)")
    func newerVersionStillRejected() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let doc = ExportSchema.Document(
            version: ExportSchema.version + 1,
            exportedAt: Date(),
            tasks: [], tags: [], journalEntries: [], attachments: [],
            preferences: .fallback,
            series: [.init(id: UUID(), seedTaskID: nil, rule: nil, nextOccurrenceAfter: nil)]
        )
        do {
            _ = try await importer.apply(document: doc, policy: .skipExisting)
            Issue.record("expected unsupportedExportVersion to be thrown")
        } catch let error as LillistError {
            #expect(error == .unsupportedExportVersion(found: ExportSchema.version + 1, supported: ExportSchema.version))
        }
    }

    @Test("A series whose seedTaskID resolves nowhere still imports — seedTask is nil, not a dropped row")
    func seriesWithUnresolvableSeedStillImports() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let seriesID = UUID()
        let danglingSeedID = UUID() // neither in the bundle nor the store
        var doc = Self.emptyDocument()
        doc.series = [ExportSchema.SeriesDTO(
            id: seriesID, seedTaskID: danglingSeedID,
            rule: .calendar(.init(freq: .weekly, interval: 2)),
            nextOccurrenceAfter: Date(timeIntervalSince1970: 1_800_000_000)
        )]
        let summary = try await importer.apply(document: doc, policy: .replaceExisting)
        #expect(summary.seriesInserted == 1)
        #expect(summary.errors.isEmpty)

        let seriesStore = SeriesStore(persistence: dst)
        let record = try await seriesStore.fetch(id: seriesID)
        #expect(record.seedTaskID == nil)
        #expect(record.rule == .calendar(.init(freq: .weekly, interval: 2)))
    }

    @Test("A reminder whose taskID resolves nowhere is skipped and recorded, not inserted task-less")
    func notificationSpecWithUnresolvableTaskSkipped() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let specID = UUID()
        var doc = Self.emptyDocument()
        doc.notificationSpecs = [ExportSchema.NotificationSpecDTO(
            id: specID, taskID: UUID(), kind: NotificationKind.nudge.rawValue,
            offsetMinutes: nil, fireDate: Date(), lastFiredAt: nil, snoozedUntil: nil, createdAt: nil
        )]
        let summary = try await importer.apply(document: doc, policy: .replaceExisting)
        #expect(summary.notificationSpecsInserted == 0)
        #expect(summary.errors.count == 1)
        #expect(summary.errors[0].contains(specID.uuidString))
    }

    @Test("skipExisting: a pre-existing task's series membership is left untouched (X13 discipline extended to the new relationship)")
    func skippedTaskSeriesMembershipUntouched() async throws {
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        let existingTaskID = try await dstTasks.create(title: "Local task, no series")

        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        let bundleSeriesID = UUID()
        doc.series = [ExportSchema.SeriesDTO(id: bundleSeriesID, seedTaskID: nil, rule: nil, nextOccurrenceAfter: nil)]
        doc.tasks = [Self.task(existingTaskID, "Local task, no series", 0, seriesID: bundleSeriesID)]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksSkipped == 1)

        let ctx = dst.container.viewContext
        let seriesID: UUID? = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", existingTaskID as CVarArg)
            req.fetchLimit = 1
            return try ctx.fetch(req).first?.series?.id
        }
        #expect(seriesID == nil, "a skipped task's series membership must not change")
    }

    @Test("skipExisting: a pre-existing series is left untouched")
    func skippedSeriesUntouched() async throws {
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        let dstSeries = SeriesStore(persistence: dst)
        let seedID = try await dstTasks.create(title: "Seed")
        let seriesID = try await dstSeries.create(fromSeedTask: seedID, rule: .calendar(.init(freq: .daily, interval: 1)))

        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        // The bundle tries to overwrite the rule — under skipExisting this
        // must have zero effect.
        doc.series = [ExportSchema.SeriesDTO(
            id: seriesID, seedTaskID: nil,
            rule: .calendar(.init(freq: .monthly, interval: 3)),
            nextOccurrenceAfter: nil
        )]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.seriesSkipped == 1)

        let after = try await dstSeries.fetch(id: seriesID)
        #expect(after.rule == .calendar(.init(freq: .daily, interval: 1)), "skipped series must not change")
    }

    // MARK: - Fixtures

    private static func emptyDocument() -> ExportSchema.Document {
        ExportSchema.Document(
            version: ExportSchema.version,
            exportedAt: Date(timeIntervalSince1970: 0),
            tasks: [], tags: [], journalEntries: [], attachments: [],
            preferences: .fallback
        )
    }

    private static func task(_ id: UUID, _ title: String, _ pos: Double, seriesID: UUID?) -> ExportSchema.TaskDTO {
        ExportSchema.TaskDTO(
            id: id, title: title, notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: pos, isPinned: false, parentID: nil, tagIDs: [],
            createdAt: Date(timeIntervalSince1970: pos), modifiedAt: nil,
            closedAt: nil, deletedAt: nil, seriesID: seriesID
        )
    }
}
