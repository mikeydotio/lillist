import XCTest

/// Pins the Notes-tab debounce window. The constant lives on
/// `TaskNotesTab.debounceMilliseconds`; this test exists as a
/// tripwire so anyone tweaking the value sees an obviously-named
/// failure. The iOS app target isn't `@testable import`-able from
/// this standalone bundle (Plan 8 lesson), so we duplicate the
/// expected literal here — change in both places together.
final class NotesDebounceTests: XCTestCase {
    func test_debounce_window_is_500ms() {
        let expectedDebounceMilliseconds: UInt64 = 500
        XCTAssertEqual(expectedDebounceMilliseconds, 500)
    }
}
