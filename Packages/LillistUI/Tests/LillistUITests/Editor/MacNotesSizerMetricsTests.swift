#if os(macOS)
import XCTest
@testable import LillistUI

/// Host-runnable guards for the macOS notes-sizer's over-count *contract* (#36).
///
/// These do **not** verify the real pixel hug — that depends on undocumented
/// `NSTextView` text-layout metrics and has no offscreen-capture path on AppKit
/// (macOS editor snapshots are `XCTSkip`-quarantined), so the actual sizing is
/// verified on-device. What they pin is the invariant relationship a future edit
/// is most likely to break: the invisible sizer must wrap *narrower* than the
/// live `TextEditor` so it can only over-count wrapped lines (adding bottom
/// slack), never under-count and clip the last line.
final class MacNotesSizerMetricsTests: XCTestCase {
    /// The sizer's horizontal inset must exceed the editor's text inset, so the
    /// sizer wraps at a narrower width and over-counts rather than clips.
    func test_sizerInset_exceedsEditorTextInset() {
        XCTAssertGreaterThan(
            TaskEditorView.macNotesSizerInset,
            TaskEditorView.macNotesTextInset,
            "Sizer must be inset more than the editor so it wraps narrower and can only over-count."
        )
    }

    /// A short-line note gets no slack from the *horizontal* over-count, so the
    /// vertical slack (and the placeholder's top inset) must be positive or the
    /// box resolves to ~the raw text height and clips the last line.
    func test_verticalInsets_arePositive() {
        XCTAssertGreaterThan(TaskEditorView.macNotesVerticalSlack, 0)
        XCTAssertGreaterThan(TaskEditorView.macNotesTopInset, 0)
    }

    /// `Text` drops a trailing newline from its measured height, so a note ending
    /// in Return must be padded with a zero-width space to keep the final line
    /// counted; an empty note falls back to a single space so the box has a floor.
    func test_sizerText_countsTrailingNewline() {
        XCTAssertEqual(TaskEditorView.macNotesSizerText(for: ""), " ")
        XCTAssertEqual(TaskEditorView.macNotesSizerText(for: "hi\n"), "hi\n\u{200B}")
        XCTAssertTrue(TaskEditorView.macNotesSizerText(for: "line").hasSuffix("\u{200B}"))
    }
}
#endif
