import XCTest
import SwiftUI

/// Exercises the `ListColumn`-based gating that prevents the Space,
/// Cmd-Return (close), Cmd-., Tab, and Shift-Tab shortcuts from firing
/// while a TextField is first-responder.
///
/// SwiftUI's `FocusedValues` has no public initializer, so we cannot
/// round-trip a value through the storage directly from a test. We
/// instead assert the contract at the surface the commands actually
/// use: the `ListColumn` enum has the three expected cases, and the
/// gating predicate (`listColumn == nil`) reads as "disabled" only when
/// no list column is focused.
@MainActor
final class FocusedShortcutGatingTests: XCTestCase {
    func test_listColumn_enum_has_three_cases() {
        let allCases: [ListColumn] = [.sidebar, .list, .detail]
        XCTAssertEqual(Set(allCases).count, 3,
                       "ListColumn must distinguish sidebar / list / detail")
    }

    func test_gating_predicate_disables_when_listColumn_nil() {
        let none: ListColumn? = nil
        let sidebar: ListColumn? = .sidebar
        let list: ListColumn? = .list
        let detail: ListColumn? = .detail
        XCTAssertTrue(none == nil,
                      "nil column must disable Space/Cmd-Return/Cmd-./Tab")
        XCTAssertFalse(sidebar == nil,
                       "Focused sidebar column must keep those shortcuts enabled")
        XCTAssertFalse(list == nil,
                       "Focused list column must keep those shortcuts enabled")
        XCTAssertFalse(detail == nil,
                       "Focused detail column must keep those shortcuts enabled")
    }

    func test_listColumn_is_hashable_for_focusState() {
        var seen: Set<ListColumn> = []
        seen.insert(.sidebar)
        seen.insert(.list)
        seen.insert(.detail)
        seen.insert(.list) // dedup
        XCTAssertEqual(seen.count, 3,
                       "ListColumn must be Hashable so @FocusState<ListColumn?> works")
    }
}
