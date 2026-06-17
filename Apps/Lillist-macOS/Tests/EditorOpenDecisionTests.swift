import XCTest
import Foundation

/// The unified editor panel's singleton rules: a quick-capture request is a
/// no-op while open (the hotkey doesn't stack or dismiss); an existing-task
/// request re-targets an open panel rather than spawning a second.
final class EditorOpenDecisionTests: XCTestCase {
    func test_quickCapture_whenClosed_presents() {
        XCTAssertEqual(
            EditorOpenDecision.decide(isOpen: false, request: .quickCapture),
            .present(.quickCapture)
        )
    }

    func test_quickCapture_whenOpen_isNoop() {
        XCTAssertEqual(
            EditorOpenDecision.decide(isOpen: true, request: .quickCapture),
            .noop
        )
    }

    func test_existing_whenClosed_presents() {
        let id = UUID()
        XCTAssertEqual(
            EditorOpenDecision.decide(isOpen: false, request: .existing(id)),
            .present(.existing(id))
        )
    }

    func test_existing_whenOpen_retargets() {
        let id = UUID()
        XCTAssertEqual(
            EditorOpenDecision.decide(isOpen: true, request: .existing(id)),
            .retarget(id)
        )
    }
}
