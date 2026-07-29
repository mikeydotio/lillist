import Testing
import Foundation
@testable import LillistCore

/// The completeness proof the 6a wave brief asks for, on top of `1d`'s two
/// existing export-completeness suites:
///
/// - `ExportSchemaCompletenessTests` (model-derived) proves every model
///   attribute/relationship has SOME mapping into a DTO field.
/// - `X3ExportSchemaCompletenessTests` proves one export captures the
///   right values for a hand-built fixture.
///
/// Neither actually re-imports what it exported. This suite closes that
/// gap: export -> import into a genuinely FRESH store -> export again,
/// then assert the two documents are equal. An importer-side bug that
/// silently drops or corrupts a field on the way IN (as opposed to never
/// having a mapping at all, which the model-derived test already catches)
/// would pass every existing test and still fail this one.
@Suite("Export/import round-trip equality (6a completeness sweep)")
struct ExportImportRoundTripEqualityTests {
    private func tempDir(_ label: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-roundtrip-\(label)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func decodeDocument(in dir: URL) throws -> ExportSchema.Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
    }

    @Test("One of everything: export -> import into a fresh store -> export again yields an equal document")
    func roundTripPreservesEveryEntity() async throws {
        let source = try await TestStore.make()
        let tasks = TaskStore(persistence: source)
        let tags = TagStore(persistence: source)
        let journal = JournalStore(persistence: source)
        let attachments = AttachmentStore(persistence: source)
        let series = SeriesStore(persistence: source)
        let specs = NotificationSpecStore(persistence: source)
        let filters = SmartFilterStore(persistence: source)
        let prefs = PreferencesStore(persistence: source)

        // Tags: a parent + child, one assigned to a task.
        let parentTagID = try await tags.create(name: "Home")
        let childTagID = try await tags.create(name: "Kitchen", parent: parentTagID)

        // Tasks: a parent (tagged) with a child, plus a separately
        // archived-and-closed task exercising archivedAt/closedAt.
        let parentTaskID = try await tasks.create(title: "Renovate")
        try await tasks.assignTag(taskID: parentTaskID, tagID: childTagID)
        _ = try await tasks.create(title: "Paint", parent: parentTaskID)
        let archivedTaskID = try await tasks.create(title: "Old chore")
        try await tasks.transition(id: archivedTaskID, to: .closed)
        _ = try await tasks.archive(ids: [archivedTaskID])

        // Journal entry + attachment on the parent task, proving asset
        // bytes survive alongside the metadata.
        _ = try await journal.appendNote(taskID: parentTaskID, body: "Called the contractor")
        let assetBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        _ = try await attachments.addFile(taskID: parentTaskID, filename: "quote.pdf", uti: "com.adobe.pdf", data: assetBytes)

        // Recurrence series + reminder off a fresh seed task.
        let seedID = try await tasks.create(title: "Water plants")
        let seriesID = try await series.create(
            fromSeedTask: seedID,
            rule: .calendar(.init(freq: .weekly, interval: 2, byDay: [.monday]))
        )
        let specID = try await specs.add(
            taskID: seedID, kind: .offsetDeadline, offsetMinutes: 30,
            fireDate: Date(timeIntervalSince1970: 2_000_000_000)
        )
        try await specs.recordLastFired(id: specID, at: Date(timeIntervalSince1970: 1_999_990_000))

        // Smart filter + a real synced preference (not a Plan-21
        // device-local field).
        _ = try await filters.create(name: "Overdue", group: .init(combinator: .all, predicates: []), tintColor: "#123456")
        try await prefs.update {
            $0.trashRetentionDays = 45
            $0.defaultTagTintHex = "#ABCDEF"
        }

        let exportDir1 = tempDir("first")
        defer { try? FileManager.default.removeItem(at: exportDir1) }
        try await Exporter(persistence: source, preferences: prefs).export(to: exportDir1)
        let doc1 = try decodeDocument(in: exportDir1)

        // Import into a genuinely FRESH, empty store — not `source` — so
        // this proves the importer alone reconstructs everything, with no
        // leftover state from the source store to lean on.
        let destination = try await TestStore.make()
        let importer = Importer(persistence: destination)
        let summary = try await importer.apply(
            document: doc1,
            policy: .replaceExisting,
            assetsDirectory: exportDir1.appendingPathComponent("assets")
        )
        #expect(summary.errors.isEmpty, "import reported errors: \(summary.errors)")

        let exportDir2 = tempDir("second")
        defer { try? FileManager.default.removeItem(at: exportDir2) }
        let destinationPrefs = PreferencesStore(persistence: destination)
        try await Exporter(persistence: destination, preferences: destinationPrefs).export(to: exportDir2)
        let doc2 = try decodeDocument(in: exportDir2)

        Self.assertDocumentsEqual(doc1, doc2, exportDir1: exportDir1, exportDir2: exportDir2)

        // Sanity: the fixture actually populated every collection this test
        // claims to cover — a fixture regression (e.g. a store call
        // silently no-op'ing) must not pass by comparing two empty lists.
        #expect(!doc1.tasks.isEmpty && !doc1.tags.isEmpty && !doc1.journalEntries.isEmpty)
        #expect(!doc1.attachments.isEmpty && !doc1.series.isEmpty && !doc1.notificationSpecs.isEmpty)
        #expect(!doc1.smartFilters.isEmpty)
        #expect(doc1.series[0].id == seriesID)
    }

    /// Compares two documents for equality modulo `exportedAt` (a fresh
    /// timestamp every export, never round-tripped by design). Every
    /// entity list is compared **as a dictionary keyed by id**, since
    /// import does not promise to preserve array order, only per-row field
    /// fidelity.
    private static func assertDocumentsEqual(
        _ a: ExportSchema.Document,
        _ b: ExportSchema.Document,
        exportDir1: URL,
        exportDir2: URL
    ) {
        #expect(a.version == b.version)
        #expect(byID(a.tasks) == byID(b.tasks))
        #expect(byID(a.tags) == byID(b.tags))
        #expect(byID(a.journalEntries) == byID(b.journalEntries))
        #expect(a.preferences == b.preferences)
        #expect(byID(a.series) == byID(b.series))
        #expect(byID(a.notificationSpecs) == byID(b.notificationSpecs))
        #expect(byID(a.smartFilters) == byID(b.smartFilters))

        // Attachments carry a `dataPath` (a per-export-relative filename),
        // not the bytes themselves — compare metadata field-by-field, then
        // compare the actual on-disk bytes under each export's own
        // `assets/` directory separately.
        let attachmentsA = byID(a.attachments)
        let attachmentsB = byID(b.attachments)
        #expect(Set(attachmentsA.keys) == Set(attachmentsB.keys))
        for (id, attA) in attachmentsA {
            guard let attB = attachmentsB[id] else { continue }
            #expect(attA.taskID == attB.taskID)
            #expect(attA.journalEntryID == attB.journalEntryID)
            #expect(attA.kind == attB.kind)
            #expect(attA.filename == attB.filename)
            #expect(attA.uti == attB.uti)
            #expect(attA.byteSize == attB.byteSize)
            guard let pathA = attA.dataPath, let pathB = attB.dataPath else {
                Issue.record("attachment \(id) lost its dataPath across the round trip")
                continue
            }
            let bytesA = try? Data(contentsOf: exportDir1.appendingPathComponent(pathA))
            let bytesB = try? Data(contentsOf: exportDir2.appendingPathComponent(pathB))
            #expect(bytesA != nil && bytesA == bytesB, "attachment \(id)'s bytes did not survive the round trip")
        }
    }

    private static func byID(_ items: [ExportSchema.TaskDTO]) -> [UUID: ExportSchema.TaskDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.TagDTO]) -> [UUID: ExportSchema.TagDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.JournalEntryDTO]) -> [UUID: ExportSchema.JournalEntryDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.AttachmentDTO]) -> [UUID: ExportSchema.AttachmentDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.SeriesDTO]) -> [UUID: ExportSchema.SeriesDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.NotificationSpecDTO]) -> [UUID: ExportSchema.NotificationSpecDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
    private static func byID(_ items: [ExportSchema.SmartFilterDTO]) -> [UUID: ExportSchema.SmartFilterDTO] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
}
