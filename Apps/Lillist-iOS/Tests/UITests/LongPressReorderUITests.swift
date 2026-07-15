import XCTest

/// First-ever real-touch coverage of row long-press drag-reorder — the
/// interaction three regressions walked through untested (dead status tap
/// 2026-06-12, gesture-composition rewrites 2026-06-17, scroll-blocked
/// issue #12): every prior suite exercised `DragController` state math or
/// snapshots, never an actual press-hold-drag-drop touch sequence.
/// Completes the issue-#12 five-interaction matrix (RCA
/// `ios-list-scroll-blocked-when`, REMEDIATION §Binding QA rider)
/// alongside `ListScrollUITests` / `SwipeDeleteUITests` /
/// `StatusCycleUITests` / `TaskTapOpenUITests`.
///
/// The gesture under test: `ReorderLongPressGesture` — a UIKit-bridged
/// `UILongPressGestureRecognizer` (0.3 s gate, 4 pt allowable movement)
/// on the row LABEL region. Hold past the gate → lift; drag → cursor;
/// release → drop reorders via `TaskStore.reorder`. Reorder is honored
/// only in personalized sort with no active filter (the default
/// fresh-store state).
///
/// Deliberately self-contained: launch/capture plumbing is duplicated
/// from `UITestHelpers` (per RCA scope rules — no shared-file edits), so
/// this file alone documents and enforces the reorder contract.
@MainActor
final class LongPressReorderUITests: XCTestCase {

    // MARK: - One-time seeding

    /// Whether this test process has already reset + seeded the store.
    /// Static so the Quick Capture round-trips happen once per run; every
    /// test then relaunches the existing store and reads the *empirical*
    /// row order at its own start, so tests stay order-independent even
    /// though the positive arm mutates the order.
    private static var hasSeeded = false

    /// Small on purpose: reorder assertions read every seeded row's
    /// frame, so all rows must be simultaneously visible (no viewport
    /// overflow). The scroll half of the sub-gate arm is covered by
    /// `ListScrollUITests`' 20-row seed instead.
    private static let seedCount = 5

    private static func seedTitle(_ index: Int) -> String {
        String(format: "Reorder seed %02d", index)
    }

    /// First call: fresh store, seed `seedCount` tasks via Quick Capture,
    /// relaunch (the unfiltered list does not reload after in-session
    /// captures). Subsequent calls: relaunch the existing store.
    private static func seededApp() -> XCUIApplication {
        if !hasSeeded {
            let fresh = launch(arguments: ["--ui-test-reset-store", "--ui-test-bypass-gates"])
            for index in 1...seedCount {
                createTask(titled: seedTitle(index), in: fresh)
            }
            fresh.terminate()
            hasSeeded = true
        }
        let app = launch(arguments: ["--ui-test-bypass-gates"])

        // Seed verification (setup, not the defect): the relaunched list
        // must show every seeded row.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if app.cells.count >= seedCount { return app }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTFail(
            "Setup failure (not the defect): expected \(seedCount) seeded rows " +
            "after relaunch, found \(app.cells.count)"
        )
        return app
    }

    /// Duplicated from `UITestHelpers.launchFresh/launchExisting` +
    /// `dismissOnboardingIfPresent` (defensive Skip poll).
    private static func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if app.buttons["TasksSettingsButton"].exists { return app }
            let skip = app.buttons["Skip for now"]
            if skip.exists {
                skip.tap()
                return app
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return app
    }

    /// Duplicated from `UITestHelpers.createTask`, with a fixed title.
    private static func createTask(titled title: String, in app: XCUIApplication) {
        let fab = app.buttons["TasksQuickCaptureFAB"]
        let emptyState = app.buttons["TasksEmptyStateCaptureButton"]
        var opened = false
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if emptyState.exists { emptyState.tap(); opened = true; break }
            if fab.exists { fab.tap(); opened = true; break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(
            opened,
            "Setup failure (not the defect): no Quick Capture entry point for '\(title)'"
        )

        let field = app.textFields["QuickCaptureField"]
        XCTAssertTrue(
            field.waitForExistence(timeout: 5),
            "Setup failure (not the defect): QuickCaptureField missing for '\(title)'"
        )
        field.tap()
        field.typeText(title)
        // The dialog has no Save button; Return submits.
        app.typeText("\n")
        let dismissDeadline = Date().addingTimeInterval(5)
        while Date() < dismissDeadline, field.exists {
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertFalse(
            field.exists,
            "Setup failure (not the defect): Quick Capture did not dismiss after '\(title)'"
        )
    }

    // MARK: - Order-reading plumbing

    /// The list cell whose subtree carries `text` in a label.
    private static func cell(in app: XCUIApplication, containing text: String) -> XCUIElement {
        app.cells
            .containing(NSPredicate(format: "label CONTAINS[c] %@", text))
            .firstMatch
    }

    /// One sample of the seeded titles' visual top-to-bottom order
    /// (titles sorted by their cells' `frame.minY`), or nil while any
    /// seeded row is missing/zero-height (mid-animation or mid-load).
    private func visualOrder(in app: XCUIApplication) -> [String]? {
        var pairs: [(title: String, minY: CGFloat)] = []
        for index in 1...Self.seedCount {
            let title = Self.seedTitle(index)
            let cell = Self.cell(in: app, containing: title)
            guard cell.exists else { return nil }
            let frame = cell.frame
            guard frame.height > 0 else { return nil }
            pairs.append((title, frame.minY))
        }
        return pairs.sorted { $0.minY < $1.minY }.map(\.title)
    }

    private struct OrderNotReadable: Error, CustomStringConvertible {
        let description =
            "Setup failure (not the defect): seeded rows never reached a " +
            "stable readable order"
    }

    /// The seeded titles' visual order once it is stable (two consecutive
    /// samples 0.3 s apart agree). Used for baselines and post-gesture
    /// settle reads — stabilizing conditions, never assertions.
    private func waitForStableOrder(
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) throws -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var previous: [String]?
        while Date() < deadline {
            let current = visualOrder(in: app)
            if let current, let previous, current == previous { return current }
            previous = current
            Thread.sleep(forTimeInterval: 0.3)
        }
        throw OrderNotReadable()
    }

    /// Post-drop read for the positive arm: poll until the visible order
    /// both differs from `baseline` and is stable, then return it. On
    /// timeout, return the last stable order — which may still equal
    /// `baseline`, so a dead gesture fails on the caller's diagnostic
    /// assertion ("row did not move"), never inside this helper.
    private func settledOrder(
        in app: XCUIApplication,
        expectingChangeFrom baseline: [String],
        timeout: TimeInterval = 6
    ) -> [String] {
        let deadline = Date().addingTimeInterval(timeout)
        var last = baseline
        var previous: [String]?
        while Date() < deadline {
            if let current = visualOrder(in: app) {
                last = current
                if current != baseline, current == previous { return current }
                previous = current
            } else {
                previous = nil
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return last
    }

    // MARK: - Gesture plumbing

    /// The long-press-drag under test, shared by all three arms so the
    /// sub-gate arm is a true minimal pair (identical geometry, only the
    /// press duration differs). Start: the dragged row's LABEL region
    /// (dx 0.6 — right of the leading status control, clear of the
    /// trailing inset; same coordinate family as `ListScrollUITests`).
    /// End: just below the target row's bottom edge, computed from
    /// pre-drag frames — valid throughout the drag because the dragged
    /// row keeps its layout slot (opacity 0) and the List cannot scroll
    /// mid-drag (no auto-scroll exists; see `ReorderLongPressGesture`).
    private func pressAndDrag(
        rowTitled draggedTitle: String,
        toBelowRowTitled targetTitle: String,
        pressDuration: TimeInterval,
        in app: XCUIApplication
    ) {
        let draggedCell = Self.cell(in: app, containing: draggedTitle)
        let targetCell = Self.cell(in: app, containing: targetTitle)
        let start = draggedCell.coordinate(
            withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)
        )
        let deltaY = (targetCell.frame.maxY + 3) - draggedCell.frame.midY
        let end = start.withOffset(CGVector(dx: 0, dy: deltaY))
        // Hold at the end point before release so the drop target has
        // resolved when the finger lifts (condition stabilization).
        start.press(
            forDuration: pressDuration,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.3
        )
    }

    // MARK: - Tests

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Positive arm: a 0.6 s press (comfortably past the 0.3 s gate) on
    /// row 2's label, dragged to below row 4, must move that row down —
    /// and the new order must survive a relaunch (store write, not just
    /// a visual shuffle).
    ///
    /// The assertion pins the behavior class — exactly one row moved
    /// down, every other row's relative order preserved, result
    /// persisted — rather than one exact permutation: the landed slot
    /// depends on the drop resolver's midpoint geometry, which is
    /// unit-tested in the DragController suites. What no other test
    /// covers, and what this one exists for, is the real-touch
    /// lift → drag → drop → store chain.
    func test_longPressDragOnRowLabel_reordersRowDownward_andPersists() throws {
        let app = Self.seededApp()
        let before = try waitForStableOrder(in: app)
        let draggedTitle = before[1]
        let targetTitle = before[3]

        pressAndDrag(
            rowTitled: draggedTitle,
            toBelowRowTitled: targetTitle,
            pressDuration: 0.6,
            in: app
        )

        let after = settledOrder(in: app, expectingChangeFrom: before)

        XCTAssertEqual(
            Set(after), Set(before),
            "Reorder lost or duplicated rows: \(before) -> \(after)"
        )
        let oldIndex = 1
        let newIndex = after.firstIndex(of: draggedTitle) ?? -1
        XCTAssertGreaterThan(
            newIndex, oldIndex,
            "Long-press drag did not move '\(draggedTitle)' down " +
            "(order \(before) -> \(after)) — the real-touch " +
            "lift/drag/drop reorder chain is dead. (If the Due-sort arm " +
            "failed earlier in this class, first check its sort restore.)"
        )
        XCTAssertEqual(
            after.filter { $0 != draggedTitle },
            before.filter { $0 != draggedTitle },
            "Drop was not a single-row move — other rows changed relative " +
            "order: \(before) -> \(after)"
        )

        // Persistence: the reorder must be a store write, not view state.
        app.terminate()
        let relaunched = Self.launch(arguments: ["--ui-test-bypass-gates"])
        let persisted = try waitForStableOrder(in: relaunched)
        XCTAssertEqual(
            persisted, after,
            "Reordered position did not persist across relaunch — the drop " +
            "reached the view but not the store"
        )
    }

    /// Negative arm (minimal pair with the positive test — identical
    /// geometry, press duration 0.05 s, under the 0.3 s gate): the touch
    /// must go to the List's scroll pan, never the reorder, so the order
    /// is unchanged in-session and after relaunch. With 5 rows there is
    /// no viewport overflow, so the "…and it scrolls" half of this arm
    /// is deliberately left to `ListScrollUITests`' 20-row seed
    /// (`test_slowDragOnRowBody_doesScroll`) — asserting rubber-band
    /// movement here would be redundant and flakier.
    func test_subGateDragOnRowLabel_doesNotReorder() throws {
        let app = Self.seededApp()
        let before = try waitForStableOrder(in: app)

        pressAndDrag(
            rowTitled: before[1],
            toBelowRowTitled: before[3],
            pressDuration: 0.05,
            in: app
        )

        let after = try waitForStableOrder(in: app)
        XCTAssertEqual(
            after, before,
            "A sub-gate (0.05 s) drag reordered rows: \(before) -> \(after) — " +
            "the 0.3 s / 4 pt long-press gate is not being enforced"
        )

        // And nothing was silently written.
        app.terminate()
        let relaunched = Self.launch(arguments: ["--ui-test-bypass-gates"])
        let persisted = try waitForStableOrder(in: relaunched)
        XCTAssertEqual(
            persisted, before,
            "Sub-gate drag persisted an order change across relaunch — a " +
            "reorder was silently written to the store"
        )
    }

    /// Negative arm: in a non-personalized sort (Due), the same
    /// long-press drag must not change the personalized order — the drop
    /// resolver returns `.none` outside personalized/unfiltered mode, so
    /// `manualPosition` stays untouched. Verified by switching back to
    /// Personalized and asserting the original order (the sort switch
    /// itself is `@AppStorage`-persisted, so the test restores it
    /// in-band and defensively in teardown).
    func test_longPressDragInDueSort_doesNotChangePersonalizedOrder() throws {
        let app = Self.seededApp()
        let before = try waitForStableOrder(in: app)

        let restoreFlag = SortRestoreFlag()
        addTeardownBlock { @MainActor in
            // Sort persists across relaunches; if this test aborted after
            // switching to Due, later tests would inherit it and fail for
            // the wrong reason. Best-effort restore on a fresh launch.
            guard restoreFlag.needsRestore else { return }
            let recovery = Self.launch(arguments: ["--ui-test-bypass-gates"])
            Self.setSort(toOptionNamed: "Personalized", in: recovery)
            recovery.terminate()
        }

        Self.setSort(toOptionNamed: "Due", in: app)
        restoreFlag.needsRestore = true
        let dueOrder = try waitForStableOrder(in: app)

        pressAndDrag(
            rowTitled: dueOrder[1],
            toBelowRowTitled: dueOrder[3],
            pressDuration: 0.6,
            in: app
        )
        // Let any (erroneous) drop land before switching back.
        _ = try waitForStableOrder(in: app)

        Self.setSort(toOptionNamed: "Personalized", in: app)
        restoreFlag.needsRestore = false
        let after = try waitForStableOrder(in: app)
        XCTAssertEqual(
            after, before,
            "A long-press drag under Due sort changed the personalized " +
            "order: \(before) -> \(after) — reorder must only be honored " +
            "in personalized sort with no active filter"
        )
    }

    /// Mutable flag shared between the Due-sort test body and its
    /// teardown block. A reference box (rather than a captured local
    /// `var`) because `addTeardownBlock`'s closure is `@Sendable`; all
    /// access happens on the main actor, so the unchecked conformance
    /// is safe.
    private final class SortRestoreFlag: @unchecked Sendable {
        var needsRestore = false
    }

    /// Select a sort option via the toolbar sort menu.
    private static func setSort(toOptionNamed option: String, in app: XCUIApplication) {
        let menu = app.buttons["TasksSortMenu"]
        XCTAssertTrue(
            menu.waitForExistence(timeout: 5),
            "Setup failure (not the defect): TasksSortMenu missing"
        )
        menu.tap()
        let item = app.buttons[option]
        XCTAssertTrue(
            item.waitForExistence(timeout: 4),
            "Setup failure (not the defect): sort option '\(option)' did not appear"
        )
        item.tap()
    }
}
