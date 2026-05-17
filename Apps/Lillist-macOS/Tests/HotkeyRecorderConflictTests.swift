import XCTest
import AppKit

final class HotkeyRecorderConflictTests: XCTestCase {

    func test_rejects_bareCommand() {
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 12 /* q */))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 13 /* w */))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [.command], keyCode: 49 /* space */))
    }

    func test_rejects_noModifier() {
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [], keyCode: 49))
        XCTAssertNil(HotkeyRecorder.encode(modifiers: [], keyCode: 12))
    }

    func test_accepts_commandWithSecondModifier() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.command, .shift], keyCode: 37 /* l */))
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.command, .option], keyCode: 35 /* p */))
    }

    func test_accepts_controlOption() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.control, .option], keyCode: 49))
    }

    func test_accepts_functionKey_withModifier() {
        XCTAssertNotNil(HotkeyRecorder.encode(modifiers: [.shift], keyCode: 122 /* f1 */))
    }
}
