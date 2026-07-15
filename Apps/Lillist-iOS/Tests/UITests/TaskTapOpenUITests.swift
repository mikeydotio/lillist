import XCTest

/// Tap-opens-editor arm of the issue-#12 five-interaction matrix (RCA
/// `ios-list-scroll-blocked-when`, REMEDIATION §Binding QA rider): a
/// quick tap on a row's label must present the unified task editor for
/// that task. The label carries an `.onTapGesture` layered with the
/// UIKit-bridged reorder long-press (`ReorderLongPressGesture`, 0.3 s
/// gate) — this test pins the tap side of that arbitration so a future
/// gesture change can't kill tap-to-open the way earlier compositions
/// killed the status tap (2026-06-12) and list scrolling (issue #12).
///
/// NOT subject to the `StatusCycleUITests` header caveat: that
/// documented XCUITest fidelity gap was about the retired
/// `NavigationLink`-to-detail *push*. Row taps now route through
/// `onOpenTask` → `TaskEditorHost`'s floating overlay
/// (`taskEditorOverlay`), which does present under synthesized taps.
@MainActor
final class TaskTapOpenUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// A quick tap (far under the 0.3 s long-press gate) on the row's
    /// label region opens the full editor, loaded with the tapped task.
    func test_quickTapOnRowLabel_opensFullEditor_forThatTask() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)

        // Tap the LABEL region (dx 0.6 — right of the leading status
        // control, clear of the trailing inset; the same coordinate
        // family the reorder/scroll tests drag on), not the cell center,
        // so this exercises exactly the surface that carries the
        // tap + long-press gesture pair.
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()

        // `EditorTitleField` exists only in the editor's FULL mode
        // (existing-task presentation) — its appearance is the "editor
        // opened" signal. Matched by identifier across element types
        // because a vertical-axis TextField's AX classification varies.
        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5),
            "Tapping the row label did not present the task editor — the " +
            "tap was eaten before reaching the label's .onTapGesture " +
            "(gesture-arbitration regression, issue #12 family)"
        )

        // Right task: `TaskEditorModel.load()` populates the title
        // asynchronously after presentation, so poll before asserting.
        let deadline = Date().addingTimeInterval(4)
        var observed = titleField.value as? String
        while Date() < deadline, observed != title {
            Thread.sleep(forTimeInterval: 0.25)
            observed = titleField.value as? String
        }
        XCTAssertEqual(
            observed, title,
            "Editor presented but did not load the tapped task — title " +
            "field shows '\(observed ?? "nil")' instead of '\(title)'"
        )
    }

    /// The #22 wrap fix nests the full-mode card in a `ViewThatFits`
    /// (wrap-else-scroll), which instantiates BOTH a plain and a scrolling
    /// copy of the card to measure them. This pins that the chosen copy's
    /// live editors stay focusable — typed text must stick — so a
    /// measurement-only "ghost" candidate can never swallow input.
    func test_fullEditor_notesField_isEditable_insideWrapValve() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()

        // Matched by identifier across element types: a vertical-axis
        // TextField's AX classification varies (textField vs textView).
        let notes = app.descendants(matching: .any)
            .matching(identifier: "EditorNotesField")
            .firstMatch
        XCTAssertTrue(
            notes.waitForExistence(timeout: 5),
            "Notes field missing in the full editor"
        )
        notes.tap()
        let typed = "wrap check note"
        notes.typeText(typed)

        let deadline = Date().addingTimeInterval(3)
        var observed = notes.value as? String
        while Date() < deadline, !(observed?.contains(typed) ?? false) {
            Thread.sleep(forTimeInterval: 0.2)
            observed = notes.value as? String
        }
        XCTAssertTrue(
            observed?.contains(typed) ?? false,
            "Typed notes did not stick inside the ViewThatFits card — the " +
            "focused editor may be a measurement-only candidate. Field " +
            "reads '\(observed ?? "nil")'"
        )
    }
}
