import Testing
import Foundation
@testable import LillistCore

@Suite("Exporter")
struct ExporterTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-export-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Empty store exports a valid document")
    func emptyStore() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        _ = try await prefs.read()
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)
        let docURL = dir.appendingPathComponent("lillist.json")
        let data = try Data(contentsOf: docURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(ExportSchema.Document.self, from: data)
        #expect(doc.version == ExportSchema.version)
        #expect(doc.tasks.isEmpty)
        #expect(doc.tags.isEmpty)
    }

    @Test("Tasks, tags, journal entries, attachments all roundtrip")
    func fullRoundtrip() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let attach = AttachmentStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)

        let tag = try await tags.create(name: "Work", tintColor: "#FF0000")
        let task = try await tasks.create(title: "Ship")
        try await tasks.assignTag(taskID: task, tagID: tag)
        _ = try await journals.appendNote(taskID: task, body: "Hello")
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        _ = try await attach.addFile(taskID: task, filename: "x.bin", uti: "public.data", data: png)

        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)

        let docURL = dir.appendingPathComponent("lillist.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: docURL)
        )

        #expect(doc.tasks.count == 1)
        #expect(doc.tasks[0].title == "Ship")
        #expect(doc.tasks[0].tagIDs == [tag])
        #expect(doc.tags.count == 1)
        #expect(doc.journalEntries.count == 2)
        #expect(doc.attachments.count == 1)

        let asset = doc.attachments[0]
        #expect(asset.dataPath != nil)
        let assetURL = dir.appendingPathComponent(asset.dataPath!)
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        #expect(try Data(contentsOf: assetURL) == png)
    }

    @Test("Export refuses to write into a non-empty directory")
    func refusesNonEmptyDir() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let occupant = dir.appendingPathComponent("hello.txt")
        try "hi".write(to: occupant, atomically: true, encoding: .utf8)
        await #expect(throws: LillistError.self) {
            try await exporter.export(to: dir)
        }
    }

    @Test("Export does not mutate or block the main-queue viewContext")
    func usesBackgroundContext() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let attach = AttachmentStore(persistence: p)
        let task = try await tasks.create(title: "Has asset")
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        _ = try await attach.addFile(taskID: task, filename: "blob.bin", uti: "public.data", data: bytes)

        let prefs = PreferencesStore(persistence: p)
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await exporter.export(to: dir)

        let viewHasChanges: Bool = await p.container.viewContext.perform {
            p.container.viewContext.hasChanges
        }
        #expect(viewHasChanges == false)

        let doc = try decodeDocument(in: dir)
        #expect(doc.attachments.count == 1)
        let path = try #require(doc.attachments[0].dataPath)
        let assetURL = dir.appendingPathComponent(path)
        #expect(try Data(contentsOf: assetURL) == bytes)
    }

    private func decodeDocument(in dir: URL) throws -> ExportSchema.Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
    }
}
