import XCTest
@testable import LillistCore

final class DiagnosticLogTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("diaglog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func event(_ name: String, _ seq: UInt64) -> DiagnosticEvent {
        DiagnosticEvent(at: Date(timeIntervalSince1970: 1_700_000_000), seq: seq, process: .app, category: .data, name: name, payload: [:])
    }

    func test_append_writes_one_jsonl_line_per_event_to_process_day_file() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: true, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        await log.log(event("task.delete", 2))
        let file = dir.appendingPathComponent("diag-2026-06-06-app.jsonl")
        let lines = try DiagnosticEvent.decodeJSONLines(String(contentsOf: file, encoding: .utf8))
        XCTAssertEqual(lines.map(\.name), ["task.create", "task.delete"])
        let dropped = await log.droppedCount()
        XCTAssertEqual(dropped, 0)
    }

    func test_disabled_log_is_a_noop() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: false, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("diag-2026-06-06-app.jsonl").path))
    }

    func test_setEnabled_toggles_writing() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: false, dayStamp: "2026-06-06")
        await log.setEnabled(true)
        await log.log(event("task.create", 1))
        let file = dir.appendingPathComponent("diag-2026-06-06-app.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func test_nil_directory_is_silent_noop_not_a_drop() async throws {
        let log = DiagnosticLog(directory: nil, process: .app, enabled: true, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        let dropped = await log.droppedCount()
        XCTAssertEqual(dropped, 0, "an unresolved directory is a no-op, not a counted I/O failure")
    }

    func test_unwritable_directory_increments_droppedCount() async throws {
        // Plant a *file* where the diagnostics directory should be, so the
        // directory creation inside `log` fails and the write is dropped.
        let base = tempDir()
        let blocked = base.appendingPathComponent("blocked", isDirectory: true)
        FileManager.default.createFile(atPath: blocked.path, contents: Data("x".utf8))
        let log = DiagnosticLog(directory: blocked, process: .app, enabled: true, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        let dropped = await log.droppedCount()
        XCTAssertEqual(dropped, 1)
    }
}
