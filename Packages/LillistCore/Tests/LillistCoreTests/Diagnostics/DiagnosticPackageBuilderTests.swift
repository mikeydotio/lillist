import XCTest
import CoreData
@testable import LillistCore

final class DiagnosticPackageBuilderTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("diagpkg-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func seedDiagnosticsDir() throws -> URL {
        let dir = tempDir()
        let day1 = DiagnosticEvent(at: Date(timeIntervalSince1970: 10), seq: 0, process: .app, category: .data, name: "task.create", payload: [:])
        let day1b = DiagnosticEvent(at: Date(timeIntervalSince1970: 20), seq: 1, process: .app, category: .ui, name: "task.reorder", payload: [:])
        let ext = DiagnosticEvent(at: Date(timeIntervalSince1970: 15), seq: 0, process: .shareExtension, category: .data, name: "task.create", payload: [:])
        try Data((try DiagnosticEvent.encodeJSONLine(day1) + DiagnosticEvent.encodeJSONLine(day1b)).utf8)
            .write(to: dir.appendingPathComponent("diag-2026-06-06-app.jsonl"))
        try Data(DiagnosticEvent.encodeJSONLine(ext).utf8)
            .write(to: dir.appendingPathComponent("diag-2026-06-06-shareExtension.jsonl"))
        return dir
    }

    private func sampleMetadata() -> DiagnosticPackageBuilder.Metadata {
        DiagnosticPackageBuilder.Metadata(
            buildVersion: "39", osVersion: "26.2", deviceModel: "iPhone17,1",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000), diagnosticLoggingEnabled: true
        )
    }

    func test_build_produces_a_nonEmpty_zip_for_logs_only() async throws {
        let dir = try seedDiagnosticsDir()
        let builder = DiagnosticPackageBuilder(diagnosticsDir: dir, storeURL: nil, metadata: sampleMetadata())
        let zip = try await builder.build(options: .init(includeLogs: true, includeStore: false))
        defer { try? FileManager.default.removeItem(at: zip) }
        XCTAssertEqual(zip.pathExtension, "zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func test_stage_writes_manifest_merged_events_and_raw_logs() throws {
        let dir = try seedDiagnosticsDir()
        let builder = DiagnosticPackageBuilder(diagnosticsDir: dir, storeURL: nil, metadata: sampleMetadata())
        let stage = try builder.stage(options: .init(includeLogs: true, includeStore: false))
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }

        // manifest.json present + lists the inventory
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(DiagnosticPackageBuilder.Metadata.self, from: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
        XCTAssertTrue(meta.files.contains("events.jsonl"))
        XCTAssertTrue(meta.files.contains("raw/diag-2026-06-06-app.jsonl"))
        XCTAssertTrue(meta.files.contains("raw/diag-2026-06-06-shareExtension.jsonl"))
        XCTAssertEqual(meta.buildVersion, "39")

        // events.jsonl present + merged in time order (at, then seq)
        let merged = try DiagnosticEvent.decodeJSONLines(String(contentsOf: stage.appendingPathComponent("events.jsonl"), encoding: .utf8))
        XCTAssertEqual(merged.map(\.at.timeIntervalSince1970), [10, 15, 20])

        // raw files copied verbatim
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("raw/diag-2026-06-06-app.jsonl").path))
    }

    func test_mergeEvents_skips_only_the_corrupt_line_not_the_whole_file() throws {
        let dir = tempDir()
        let good1 = DiagnosticEvent(at: Date(timeIntervalSince1970: 10), seq: 0, process: .app, category: .data, name: "a", payload: [:])
        let good2 = DiagnosticEvent(at: Date(timeIntervalSince1970: 30), seq: 1, process: .app, category: .data, name: "b", payload: [:])
        // A torn middle line (process killed mid-write) must not drop a/b.
        let blob = try DiagnosticEvent.encodeJSONLine(good1) + "{ this is not valid json\n" + DiagnosticEvent.encodeJSONLine(good2)
        let file = dir.appendingPathComponent("diag-2026-06-06-app.jsonl")
        try Data(blob.utf8).write(to: file)
        let merged = DiagnosticPackageBuilder.mergeEvents(from: [file])
        XCTAssertEqual(merged.map(\.name), ["a", "b"], "corrupt line skipped; surrounding events survive")
    }

    func test_includeStore_with_missing_store_file_degrades_to_logs_with_a_note() throws {
        let dir = try seedDiagnosticsDir()
        let missing = tempDir().appendingPathComponent("does-not-exist.sqlite")
        let builder = DiagnosticPackageBuilder(diagnosticsDir: dir, storeURL: missing, metadata: sampleMetadata())
        // Must NOT throw — the package degrades to logs-only.
        let stage = try builder.stage(options: .init(includeLogs: true, includeStore: true))
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("events.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("store/Lillist.sqlite").path))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(DiagnosticPackageBuilder.Metadata.self, from: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
        XCTAssertTrue(meta.notes.contains { $0.contains("store snapshot failed") })
    }

    func test_build_with_zero_log_files_still_produces_a_valid_package() async throws {
        let emptyDir = tempDir()   // no diag files
        let builder = DiagnosticPackageBuilder(diagnosticsDir: emptyDir, storeURL: nil, metadata: sampleMetadata())
        let stage = try builder.stage(options: .init(includeLogs: true, includeStore: false))
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        // events.jsonl exists but is empty; manifest still lists it.
        let merged = try String(contentsOf: stage.appendingPathComponent("events.jsonl"), encoding: .utf8)
        XCTAssertTrue(merged.isEmpty)
        let zip = try await builder.build(options: .init(includeLogs: true, includeStore: false))
        defer { try? FileManager.default.removeItem(at: zip) }
        XCTAssertGreaterThan((try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? Int) ?? 0, 0)
    }

    func test_mergeEvents_sorts_by_at_then_seq() throws {
        let dir = try seedDiagnosticsDir()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let merged = DiagnosticPackageBuilder.mergeEvents(from: files)
        XCTAssertEqual(merged.map(\.at.timeIntervalSince1970), [10, 15, 20])
    }

    func test_snapshot_store_is_a_complete_openable_db_with_expected_rows() async throws {
        // On-disk localOnly store with 3 tasks (kept open so the read-only
        // snapshot connection can read the live WAL — matching production, where
        // the app holds the store open).
        let storeURL = tempDir().appendingPathComponent("Lillist.sqlite")
        let persistence = try await PersistenceController(configuration: .onDisk(url: storeURL, syncMode: .localOnly))
        let store = TaskStore(persistence: persistence)
        for title in ["a", "b", "c"] { _ = try await store.create(title: title) }

        let dest = tempDir().appendingPathComponent("snapshot.sqlite")
        try DiagnosticPackageBuilder.snapshotStore(at: storeURL, into: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))

        // Reopen the snapshot with a fresh, read-only coordinator using the same
        // model and assert the row count survived intact.
        let model = persistence.container.managedObjectModel
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: dest, options: [NSReadOnlyPersistentStoreOption: true])
        let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: "LillistTask"))
        }
        XCTAssertEqual(count, 3)
    }

    func test_includeStore_with_nil_url_notes_skip_in_manifest() throws {
        let dir = try seedDiagnosticsDir()
        let builder = DiagnosticPackageBuilder(diagnosticsDir: dir, storeURL: nil, metadata: sampleMetadata())
        let stage = try builder.stage(options: .init(includeLogs: false, includeStore: true))
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let meta = try decoder.decode(DiagnosticPackageBuilder.Metadata.self, from: Data(contentsOf: stage.appendingPathComponent("manifest.json")))
        XCTAssertTrue(meta.notes.contains { $0.contains("no on-disk store URL") })
        XCTAssertFalse(meta.files.contains { $0.hasPrefix("store/") })
    }

    func test_logs_excluded_when_includeLogs_false() throws {
        let dir = try seedDiagnosticsDir()
        let builder = DiagnosticPackageBuilder(diagnosticsDir: dir, storeURL: nil, metadata: sampleMetadata())
        let stage = try builder.stage(options: .init(includeLogs: false, includeStore: false))
        defer { try? FileManager.default.removeItem(at: stage.deletingLastPathComponent()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("events.jsonl").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("raw").path))
    }
}
