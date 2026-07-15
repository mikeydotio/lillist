import XCTest

/// macOS real-input coverage of tap-to-open — the click side of the row
/// label's tap/drag arbitration (issue #18 evidence).
///
/// A plain click (no drag) on a row must open the unified editor loaded with
/// that task; the co-located reorder `DragGesture` must not swallow the
/// click. The macOS analogue of the iOS `TaskTapOpenUITests`, guarding
/// against a future gesture change killing click-to-open the way earlier
/// iOS compositions killed the status tap and list scrolling.
///
/// macOS UITests are not run in CI; this is the standing regression guard
/// for a manual run on a signed Mac.
@MainActor
final class MacRowTapOpenUITests: XCTestCase {

    private static let seedCount = 5

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A plain click on a row's label opens the full editor, loaded with the
    /// clicked task.
    func test_clickOnRow_opensEditor_forThatTask() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let titles = (1...Self.seedCount).map { MacUITestHelpers.seedTitle($0) }
        let order = try waitForStableOrder(in: app, titles: titles)
        let target = order[0]

        let row = MacUITestHelpers.rowElement(in: app, containing: target)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // `EditorTitleField` exists only in the editor's full mode
        // (existing-task presentation) — its appearance is the "editor
        // opened" signal. Matched by identifier across element types because
        // a vertical-axis TextField's AX classification varies.
        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5),
            "Clicking the row did not open the task editor — the click was " +
            "eaten before reaching the label's .onTapGesture."
        )

        // Right task: the editor loads the title asynchronously after present.
        let deadline = Date().addingTimeInterval(4)
        var observed = titleField.value as? String
        while Date() < deadline, observed != target {
            Thread.sleep(forTimeInterval: 0.25)
            observed = titleField.value as? String
        }
        XCTAssertEqual(
            observed, target,
            "Editor opened but loaded '\(observed ?? "nil")' instead of '\(target)'"
        )
    }
}
