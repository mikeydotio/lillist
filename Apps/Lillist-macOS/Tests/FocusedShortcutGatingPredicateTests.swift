import XCTest
import SwiftUI

/// Asserts the *shipping* focus-gating predicate — not a re-typed copy.
/// `TaskListShortcutGate.isDisabled(listColumn:)` is the single source the
/// Space / Cmd-Return / Cmd-. `.disabled(...)` modifiers call; gating those
/// shortcuts off only when no list column holds focus keeps them from firing
/// while a TextField is first responder.
///
/// Bare imports (`XCTest` + `SwiftUI`), matching the existing
/// `FocusedShortcutGatingTests.swift` — the `Lillist-macOSTests` bundle is
/// standalone (no app test host) and co-compiles `FocusedListColumn.swift`
/// directly, so both `ListColumn` and `TaskListShortcutGate` are in-scope
/// without a `@testable import`.
@MainActor
final class FocusedShortcutGatingPredicateTests: XCTestCase {
    func test_nilColumn_disablesShortcuts() {
        XCTAssertTrue(
            TaskListShortcutGate.isDisabled(listColumn: nil),
            "No focused list column must disable Space/Cmd-Return/Cmd-."
        )
    }

    func test_focusedColumns_enableShortcuts() {
        XCTAssertFalse(TaskListShortcutGate.isDisabled(listColumn: .sidebar))
        XCTAssertFalse(TaskListShortcutGate.isDisabled(listColumn: .list))
    }

    func test_listColumn_hasExactlyTwoCases() {
        // `.detail` retired with the docked detail column.
        XCTAssertEqual(Set<ListColumn>([.sidebar, .list]).count, 2)
    }
}
