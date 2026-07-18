import XCTest

/// macOS real-input coverage of the notes-field Return key (issue #29).
///
/// A vertical-axis `TextField` routes **Return → submit** on AppKit, so hard
/// line breaks needed Option-Return — the reverse of iOS. The macOS notes field
/// is now a bounded `TextEditor` (issue #29 redesign), so plain Return must
/// insert a newline. This pins that behavior: it would have failed on the old
/// vertical-axis `TextField` (Return submitted, no newline) and passes on the
/// `TextEditor`.
///
/// macOS UITests are not run in CI; this is the standing regression guard for a
/// manual run on a signed Mac.
@MainActor
final class MacNotesFieldUITests: XCTestCase {

    private static let seedCount = 5

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Typing two Return-separated lines into the notes field leaves a newline
    /// in the value — Return inserts a break, it does not submit.
    func test_notesField_returnInsertsNewline() throws {
        let app = MacUITestHelpers.launchGestureSeeded(count: Self.seedCount)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30),
                      "Main window never appeared")
        let titles = (1...Self.seedCount).map { MacUITestHelpers.seedTitle($0) }
        let order = try waitForStableOrder(in: app, titles: titles)
        let target = order[0]

        let row = MacUITestHelpers.rowElement(in: app, containing: target)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        // Wait for the editor to open (title field is the "opened" signal) and
        // finish loading the task before touching the notes field.
        let titleField = app.descendants(matching: .any)
            .matching(identifier: "EditorTitleField")
            .firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), "Editor did not open")
        let loadDeadline = Date().addingTimeInterval(5)
        while Date() < loadDeadline, (titleField.value as? String) != target {
            Thread.sleep(forTimeInterval: 0.2)
        }

        // Matched by identifier across element types: a TextEditor's AX
        // classification is a text view, distinct from the title TextField.
        let notes = app.descendants(matching: .any)
            .matching(identifier: "EditorNotesField")
            .firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 5), "Notes field missing")
        notes.click()
        notes.typeText("line one\nline two")

        // The value must carry a newline between the two lines. On the old
        // vertical-axis TextField, Return submitted instead of breaking the
        // line, so no newline would be present.
        let deadline = Date().addingTimeInterval(3)
        var observed = notes.value as? String
        while Date() < deadline, !(observed?.contains("\n") ?? false) {
            Thread.sleep(forTimeInterval: 0.2)
            observed = notes.value as? String
        }
        XCTAssertTrue(
            observed?.contains("\n") ?? false,
            "Return did not insert a newline in the macOS notes field — it read " +
            "'\(observed ?? "nil")' (Return submitted instead of breaking the line)"
        )
        XCTAssertTrue(
            (observed?.contains("line one") ?? false) && (observed?.contains("line two") ?? false),
            "Both typed lines should be present; field reads '\(observed ?? "nil")'"
        )
    }
}
