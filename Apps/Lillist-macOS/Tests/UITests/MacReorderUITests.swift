import XCTest

/// macOS real-input coverage of row drag-reorder — the desktop evidence for
/// issue #18's `DragReorderable` macOS branch.
///
/// On macOS the reorder gesture is a bare `DragGesture(minimumDistance: 4)`
/// with axis arbitration (`DragAxisArbiter`) and *no* long-press gate: a
/// *vertical* click-drag on a row commits the reorder; a *horizontal* drag
/// is yielded to the swipe gesture. Both arms are pinned here against the
/// real synthesized mouse drag → shared `DragController` → `TaskStore
/// .reorder` chain, the first behavioral coverage of macOS reorder.
///
/// macOS UITests are not run in CI; this is the standing regression guard
/// for a manual run on a signed Mac.
@MainActor
final class MacReorderUITests: XCTestCase {

    /// Small so every seeded row is simultaneously visible (no overflow):
    /// the order-read assertions need every seeded row's frame.
    private static let seedCount = 5

    private static func titles() -> [String] {
        (1...seedCount).map { MacUITestHelpers.seedTitle($0) }
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A vertical click-drag on a row's label, dragged below a lower row,
    /// moves that row down — and the new order survives a relaunch (a store
    /// write, not a view shuffle). The assertion pins the behavior class
    /// (exactly one row moved down, others preserved, persisted) rather than
    /// one exact permutation — the landed slot depends on the drop resolver's
    /// midpoint geometry, unit-tested in the shared DragController suites.
    func test_verticalDragOnRow_reordersDown_andPersists() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let before = try waitForStableOrder(in: app, titles: Self.titles())
        let draggedTitle = before[1]
        let targetTitle = before[3]

        dragRow(draggedTitle, belowRow: targetTitle, in: app)

        let after = settledOrder(in: app, titles: Self.titles(), changingFrom: before)
        XCTAssertEqual(Set(after), Set(before),
                       "Reorder lost or duplicated rows: \(before) -> \(after)")
        let newIndex = after.firstIndex(of: draggedTitle) ?? -1
        XCTAssertGreaterThan(
            newIndex, 1,
            "Vertical drag did not move '\(draggedTitle)' down (order " +
            "\(before) -> \(after)) — the macOS real-input reorder chain is dead."
        )
        XCTAssertEqual(
            after.filter { $0 != draggedTitle },
            before.filter { $0 != draggedTitle },
            "Drop was not a single-row move — other rows changed relative " +
            "order: \(before) -> \(after)"
        )

        // Persistence: the reorder must be a store write, not view state.
        app.terminate()
        let relaunched = MacUITestHelpers.launchExistingStore()
        let persisted = try waitForStableOrder(in: relaunched, titles: Self.titles())
        XCTAssertEqual(
            persisted, after,
            "Reordered position did not persist across relaunch — the drop " +
            "reached the view but not the store"
        )
    }

    /// A *horizontal* click-drag on the same row must not reorder — the axis
    /// arbiter yields horizontal motion to the swipe gesture, so the vertical
    /// order is unchanged.
    func test_horizontalDragOnRow_doesNotReorder() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let before = try waitForStableOrder(in: app, titles: Self.titles())

        let row = MacUITestHelpers.rowElement(in: app, containing: before[1])
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: -120, dy: 0))
        MacUITestHelpers.dragMouse(from: start, to: end)

        let after = try waitForStableOrder(in: app, titles: Self.titles())
        XCTAssertEqual(
            after, before,
            "A horizontal drag reordered rows: \(before) -> \(after) — the " +
            "axis arbiter is not yielding horizontal motion to the swipe."
        )
    }

    // MARK: - Gesture + settle plumbing

    /// Vertical click-drag: start on the dragged row's label (dx 0.5), end
    /// just past the target row's bottom edge, computed from pre-drag frames
    /// (valid throughout: the dragged row keeps its layout slot and the list
    /// cannot scroll mid-drag — no macOS auto-scroll).
    private func dragRow(
        _ draggedTitle: String,
        belowRow targetTitle: String,
        in app: XCUIApplication
    ) {
        let dragged = MacUITestHelpers.rowElement(in: app, containing: draggedTitle)
        let target = MacUITestHelpers.rowElement(in: app, containing: targetTitle)
        let start = dragged.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let deltaY = (target.frame.maxY + 3) - dragged.frame.midY
        let end = start.withOffset(CGVector(dx: 0, dy: deltaY))
        MacUITestHelpers.dragMouse(from: start, to: end, holdDuration: 0.15)
    }

    /// Post-drop read: poll until the order both differs from `baseline` and
    /// is stable (two samples agree), else return the last stable order —
    /// which may still equal `baseline`, so a dead gesture fails on the
    /// caller's diagnostic assertion, never inside this helper.
    private func settledOrder(
        in app: XCUIApplication,
        titles: [String],
        changingFrom baseline: [String],
        timeout: TimeInterval = 6
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var lastStable = baseline
        var previous: [String]?
        while Date() < deadline {
            if let current = MacUITestHelpers.visualOrder(in: app, titles: titles) {
                if current == previous {
                    lastStable = current
                    if current != baseline { return current }
                }
                previous = current
            } else {
                previous = nil
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return lastStable
    }
}
