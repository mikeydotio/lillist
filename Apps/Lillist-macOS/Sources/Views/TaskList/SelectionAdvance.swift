import Foundation

/// Pure index-math for advancing a `List(selection:)` cursor by ±1
/// within an ordered list of IDs.
///
/// SwiftUI's `List(selection:)` on macOS 15+ supports up/down arrow
/// navigation out of the box when the list has focus, and the
/// `RootSplitView.focusedColumn = .list` wiring gives `TaskListView`'s
/// list keyboard focus on appearance. This helper exists so the
/// behavior is documented and regression-tested: if a future SwiftUI
/// revision changes the default, swap to an explicit `.onKeyPress` on
/// the list and route through `advance(...)`.
enum SelectionAdvance {
    /// - Parameters:
    ///   - current: The currently-selected ID, or nil if nothing is selected.
    ///   - ordered: The flat ID list shown in the list, in visible order.
    ///   - direction: +1 for down-arrow, -1 for up-arrow.
    /// - Returns: The next selection. Clamps at both ends; returns `current`
    ///   unchanged if `ordered` is empty or the cursor is already at the end.
    static func advance(current: UUID?, ordered: [UUID], direction: Int) -> UUID? {
        guard !ordered.isEmpty else { return current }
        guard let current, let idx = ordered.firstIndex(of: current) else {
            // No selection (or stale selection) → select the first or last.
            return direction >= 0 ? ordered.first : ordered.last
        }
        let next = idx + direction
        let clamped = max(0, min(ordered.count - 1, next))
        return ordered[clamped]
    }
}
