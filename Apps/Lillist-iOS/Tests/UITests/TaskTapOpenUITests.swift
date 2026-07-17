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

    /// The full-mode card wraps its content and scrolls only on overflow
    /// (`WrapToContentThenScroll`, post-#32; the #22 wrap fix originally used a
    /// `ViewThatFits`). This pins that the notes editor inside that wrap card
    /// stays focusable — typed text must stick — so the wrap/scroll plumbing
    /// never swallows input.
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

        // Wait for the async `TaskEditorModel.load()` to settle before typing:
        // it seeds every scalar (including notes = "") after presentation, so a
        // load that lands mid-type would clobber the keystrokes. The title
        // arriving is the "load finished" signal (same guard as the tap-open test).
        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        let loadDeadline = Date().addingTimeInterval(5)
        while Date() < loadDeadline, (titleField.value as? String) != title {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(titleField.value as? String, title,
                       "Editor never finished loading the task before the edit")

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
            "Typed notes did not stick inside the wrap card — the focused editor " +
            "may not be the live one. Field reads '\(observed ?? "nil")'"
        )
    }

    /// Smoke test of the `+ Tag` inline field's open-and-type flow on a
    /// title-only task: tapping the pill opens the field and typed text sticks.
    /// It does NOT cross the wrap card's fit boundary — a title-only card fits
    /// the offered height with the keyboard up, so the card never scrolls and
    /// this would stay green even with the tag state re-internalized. The
    /// boundary-crossing survival claim is pinned separately by
    /// `test_fullEditor_tagField_survivesKeyboardCrossingFitBoundary` (#27).
    func test_fullEditor_tagField_opensAndAcceptsInput() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()

        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Editor did not open")
        let loadDeadline = Date().addingTimeInterval(5)
        while Date() < loadDeadline, (titleField.value as? String) != title {
            Thread.sleep(forTimeInterval: 0.2)
        }

        let addTag = app.buttons["AddTagButton"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 5), "The + Tag pill is missing")
        addTag.tap()

        let tagField = app.descendants(matching: .any)
            .matching(identifier: "TagAssignmentField")
            .firstMatch
        XCTAssertTrue(
            tagField.waitForExistence(timeout: 3),
            "The inline tag field did not open after tapping + Tag"
        )
        tagField.typeText("urgent")

        let deadline = Date().addingTimeInterval(3)
        var observed = tagField.value as? String
        while Date() < deadline, !(observed?.contains("urgent") ?? false) {
            Thread.sleep(forTimeInterval: 0.2)
            observed = tagField.value as? String
        }
        XCTAssertTrue(
            observed?.contains("urgent") ?? false,
            "Typed tag draft did not stick in the hoisted tag field — it may " +
            "have collapsed. Field reads '\(observed ?? "nil")'"
        )
    }

    /// Drill-in boundary (issue #26): hoisting the tag-edit state to
    /// `TaskEditorView` widened its lifetime from the *card* to the *editor*,
    /// and `route` is `@State` on that same view — so drilling into a child and
    /// returning re-evaluates `body` without destroying identity. Without a
    /// reset, `isTagEditing` survives the round-trip and the field re-presents
    /// on Back, focused and holding a stale draft (and `TagAssignmentField`'s
    /// `.onAppear` re-raises the keyboard). This pins that a deliberate drill-in
    /// collapses the field: it must fail before the `.onChange(of: route)` reset
    /// and pass after.
    func test_fullEditor_tagField_collapsesAfterDrillInAndBack() throws {
        let (app, title) = UITestHelpers.launchWithOneTask()
        let cell = UITestHelpers.cell(in: app, containing: title)
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()

        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Editor did not open")
        let loadDeadline = Date().addingTimeInterval(5)
        while Date() < loadDeadline, (titleField.value as? String) != title {
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Open the inline tag field and type a partial, uncommitted draft.
        let addTag = app.buttons["AddTagButton"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 5), "The + Tag pill is missing")
        addTag.tap()

        let tagField = app.descendants(matching: .any)
            .matching(identifier: "TagAssignmentField")
            .firstMatch
        XCTAssertTrue(
            tagField.waitForExistence(timeout: 3),
            "The inline tag field did not open after tapping + Tag"
        )
        tagField.typeText("wor")

        // Drill into the Schedule child. A SwiftUI Button tap does NOT resign
        // the tag field's first responder, so this is a route change, not a
        // tap-away — exactly the path that left the state alive pre-fix.
        let scheduleRow = app.descendants(matching: .any)
            .matching(identifier: "EditorScheduleRow")
            .firstMatch
        XCTAssertTrue(scheduleRow.waitForExistence(timeout: 3), "Schedule row missing")
        scheduleRow.tap()

        let back = app.buttons["EditorChildBackButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "Child Back button missing")
        back.tap()

        // Back on the main card, the field must be collapsed: the + Tag pill is
        // shown again and no inline tag field (hence no stale "wor" draft, no
        // unbidden keyboard) is present. `.animation(value: route)` settles the
        // rebuild quickly, so poll the pill's return.
        XCTAssertTrue(
            addTag.waitForExistence(timeout: 3),
            "The + Tag pill did not return after drill-in → Back — the tag field " +
            "re-presented with the hoisted state still set (issue #26)"
        )
        // Give any re-presentation a beat to appear before asserting absence.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertFalse(
            tagField.exists,
            "The inline tag field re-opened after drill-in → Back, holding the " +
            "abandoned draft (issue #26 regression)"
        )
    }

    /// The tag field must survive a genuine keyboard-driven crossing of the wrap
    /// card's fit boundary (#27). A fat-notes task makes the card tall enough
    /// that it hugs its content with the keyboard down but overflows the offered
    /// height once tapping `+ Tag` raises the keyboard — so the single
    /// wrap-then-scroll subtree engages its scroll in place. (Before #32 this was
    /// a `ViewThatFits` candidate swap that tore the focused field down and
    /// dropped its draft; #32 replaced the valve with one non-swapping subtree.)
    /// The open field and its typed draft must persist through that relayout.
    /// Reverting #32 — restoring the candidate swap — regresses this loudly: the
    /// field collapses and `TagAssignmentField` never re-appears.
    func test_fullEditor_tagField_survivesKeyboardCrossingFitBoundary() throws {
        let (app, title) = UITestHelpers.launchWithFatNotesTask()
        let cell = UITestHelpers.cell(in: app, containing: title)
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()

        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Editor did not open")
        let loadDeadline = Date().addingTimeInterval(5)
        while Date() < loadDeadline, (titleField.value as? String) != title {
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Tapping + Tag opens the inline field, focuses it, and raises the
        // keyboard — which shrinks the offered height below the fat card's
        // natural height, so the single wrap-then-scroll subtree scrolls in
        // place. No candidate swap, so the focused field is never torn down.
        let addTag = app.buttons["AddTagButton"]
        XCTAssertTrue(addTag.waitForExistence(timeout: 5), "The + Tag pill is missing")
        addTag.tap()

        // The field must still be present AFTER the keyboard-driven relayout.
        // If #32's swap were restored, the field would be torn down here.
        let tagField = app.descendants(matching: .any)
            .matching(identifier: "TagAssignmentField")
            .firstMatch
        XCTAssertTrue(
            tagField.waitForExistence(timeout: 4),
            "The inline tag field did not survive the keyboard-driven boundary " +
            "crossing — it collapsed to the + Tag pill (a #32 regression)"
        )
        tagField.typeText("urgent")

        let deadline = Date().addingTimeInterval(3)
        var observed = tagField.value as? String
        while Date() < deadline, !(observed?.contains("urgent") ?? false) {
            Thread.sleep(forTimeInterval: 0.2)
            observed = tagField.value as? String
        }
        XCTAssertTrue(
            observed?.contains("urgent") ?? false,
            "Typed tag draft did not stick across the keyboard-driven boundary " +
            "crossing — the field may have collapsed mid-edit. Field reads " +
            "'\(observed ?? "nil")'"
        )
    }
}
