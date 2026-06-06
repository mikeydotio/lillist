import XCTest
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

    func test_mergeEvents_sorts_by_at_then_seq() throws {
        let dir = try seedDiagnosticsDir()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let merged = DiagnosticPackageBuilder.mergeEvents(from: files)
        XCTAssertEqual(merged.map(\.at.timeIntervalSince1970), [10, 15, 20])
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
