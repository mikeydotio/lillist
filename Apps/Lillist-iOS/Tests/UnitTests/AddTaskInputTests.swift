import XCTest

/// `AddTaskInput` (co-compiled into this bundle from the ShortcutsActions
/// extension) normalizes the spoken/typed title for `AddTaskIntent`. The
/// intent itself needs a ShortcutsActions test host to run, so the pure
/// normalizer is extracted and pinned here (mirrors `ReportCrashIntentTests`).
final class AddTaskInputTests: XCTestCase {
    func test_trimsSurroundingWhitespace() {
        XCTAssertEqual(AddTaskInput.normalizedTitle("  buy milk  "), "buy milk")
        XCTAssertEqual(AddTaskInput.normalizedTitle("\n\tcall mum\n"), "call mum")
    }

    func test_keepsInteriorContent() {
        XCTAssertEqual(AddTaskInput.normalizedTitle("pay the gas bill"), "pay the gas bill")
    }

    func test_nilForEmptyOrWhitespaceOnly() {
        XCTAssertNil(AddTaskInput.normalizedTitle(nil))
        XCTAssertNil(AddTaskInput.normalizedTitle(""))
        XCTAssertNil(AddTaskInput.normalizedTitle("    "))
        XCTAssertNil(AddTaskInput.normalizedTitle("\n\t "))
    }
}
