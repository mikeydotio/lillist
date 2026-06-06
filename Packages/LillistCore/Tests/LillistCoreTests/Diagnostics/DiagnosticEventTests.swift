import XCTest
@testable import LillistCore

final class DiagnosticEventTests: XCTestCase {
    func test_jsonl_roundTrips_singleLine_noEmbeddedNewlines() throws {
        let event = DiagnosticEvent(
            at: Date(timeIntervalSince1970: 1_700_000_000),
            seq: 7,
            process: .app,
            category: .ui,
            name: "task.reorder",
            // NB: afterPosition uses a *fractional* double on purpose. JSON has no
            // int/double distinction, so an integral double (e.g. 2.0) serializes as
            // `2` and decodes back as `.int(2)` — see test_integralDouble_normalizes.
            payload: ["afterPosition": .double(2.5), "title": .string("buy milk\nand eggs"), "threwError": .bool(true), "parentID": .null]
        )
        let line = try DiagnosticEvent.encodeJSONLine(event)
        XCTAssertFalse(line.dropLast().contains("\n"), "only the trailing terminator may be a newline")
        XCTAssertTrue(line.hasSuffix("\n"))
        let decoded = try DiagnosticEvent.decodeJSONLine(line)
        XCTAssertEqual(decoded, event)
    }

    func test_decodes_a_full_file_of_lines() throws {
        let a = DiagnosticEvent(at: Date(timeIntervalSince1970: 1), seq: 1, process: .shareExtension, category: .data, name: "task.create", payload: [:])
        let b = DiagnosticEvent(at: Date(timeIntervalSince1970: 2), seq: 2, process: .app, category: .data, name: "task.delete", payload: [:])
        let blob = try DiagnosticEvent.encodeJSONLine(a) + DiagnosticEvent.encodeJSONLine(b)
        XCTAssertEqual(try DiagnosticEvent.decodeJSONLines(blob), [a, b])
    }

    /// JSON numbers carry no int/double tag, so an integral double normalizes to
    /// `.int` on decode. This is intentional for a diagnostics value model (YAGNI:
    /// no tagged-number encoding to preserve a distinction nothing relies on).
    func test_integralDouble_normalizesToInt_byDesign() throws {
        let event = DiagnosticEvent(at: Date(timeIntervalSince1970: 1), seq: 1, process: .app, category: .ui, name: "x", payload: ["p": .double(2.0)])
        let decoded = try DiagnosticEvent.decodeJSONLine(try DiagnosticEvent.encodeJSONLine(event))
        XCTAssertEqual(decoded.payload["p"], .int(2))
    }

    func test_decodeJSONLines_ignoresBlankLines() throws {
        let a = DiagnosticEvent(at: Date(timeIntervalSince1970: 1), seq: 1, process: .cli, category: .lifecycle, name: "process.start", payload: [:])
        let blob = "\n" + (try DiagnosticEvent.encodeJSONLine(a)) + "\n"
        XCTAssertEqual(try DiagnosticEvent.decodeJSONLines(blob), [a])
    }
}
