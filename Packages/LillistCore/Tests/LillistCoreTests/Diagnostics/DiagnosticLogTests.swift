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

    func test_day_rollover_writes_to_distinct_files_and_reopens_handle() async throws {
        let dir = tempDir()
        // No pinned dayStamp → each event's `at` drives the file's day.
        let log = DiagnosticLog(directory: dir, process: .app, enabled: true)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = Calendar(identifier: .gregorian).date(byAdding: .day, value: 2, to: day1)!
        let stamp1 = DiagnosticLog.utcDayStamp(day1)
        let stamp2 = DiagnosticLog.utcDayStamp(day2)
        await log.log(DiagnosticEvent(at: day1, seq: 1, process: .app, category: .data, name: "a", payload: [:]))
        await log.log(DiagnosticEvent(at: day2, seq: 2, process: .app, category: .data, name: "b", payload: [:]))
        // Write one more on day1 to prove the handle reopens correctly (append, not clobber).
        await log.log(DiagnosticEvent(at: day1, seq: 3, process: .app, category: .data, name: "c", payload: [:]))
        let file1 = dir.appendingPathComponent("diag-\(stamp1)-app.jsonl")
        let file2 = dir.appendingPathComponent("diag-\(stamp2)-app.jsonl")
        XCTAssertNotEqual(stamp1, stamp2)
        let lines1 = try DiagnosticEvent.decodeJSONLines(String(contentsOf: file1, encoding: .utf8))
        let lines2 = try DiagnosticEvent.decodeJSONLines(String(contentsOf: file2, encoding: .utf8))
        XCTAssertEqual(lines1.map(\.name), ["a", "c"])
        XCTAssertEqual(lines2.map(\.name), ["b"])
    }

    func test_pruneOldFiles_deletes_only_files_older_than_window() async throws {
        let dir = tempDir()
        let names = [
            "diag-2026-06-06-app.jsonl",        // now → keep
            "diag-2026-05-07-app.jsonl",        // == cutoff (30 days before) → keep
            "diag-2026-05-06-app.jsonl",        // 31 days before → delete
            "diag-2026-04-01-shareExtension.jsonl", // way old → delete
            "notes.txt",                         // non-diag → untouched
        ]
        for n in names {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(n).path, contents: Data("{}\n".utf8))
        }
        let log = DiagnosticLog(directory: dir, process: .app, enabled: true)
        let now = DiagnosticEvent(at: isoDay("2026-06-06"), seq: 0, process: .app, category: .lifecycle, name: "x", payload: [:]).at
        await log.pruneOldFiles(olderThanDays: 30, now: now)
        let survivors = Set(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).map(\.lastPathComponent))
        XCTAssertEqual(survivors, ["diag-2026-06-06-app.jsonl", "diag-2026-05-07-app.jsonl", "notes.txt"])
    }

    private func isoDay(_ stamp: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: stamp)!
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
