import Testing
import AppKit

/// Plan 11 Task 17 — encoder coverage for the NSEvent-based hotkey
/// recorder.
///
/// The macOS test bundle is standalone (`TEST_HOST=""`) and therefore
/// cannot `@testable import Lillist_macOS`. Following the Plan 8
/// engineering-note pattern (see `docs/engineering-notes.md`,
/// 2026-05-14 entry, point 4), `HotkeyRecorder.swift` is co-compiled
/// into the test bundle via `Apps/project.yml`. That makes the
/// non-public `encode(modifiers:keyCode:)` reachable directly without
/// needing an app test host.
@Suite("HotkeyRecorder encoder")
struct HotkeyRecorderTests {
    @Test("Control+Option+Space encodes as 'ctrl+opt+space'")
    func ctrlOptSpace() {
        let s = HotkeyRecorder.encode(modifiers: [.control, .option], keyCode: 49) // 49 = Space
        #expect(s == "ctrl+opt+space")
    }

    @Test("Command+Shift+L encodes as 'cmd+shift+l'")
    func cmdShiftL() {
        let s = HotkeyRecorder.encode(modifiers: [.command, .shift], keyCode: 37) // 37 = 'l'
        #expect(s == "cmd+shift+l")
    }

    @Test("Unsupported keyCode produces nil")
    func unsupportedKey() {
        let s = HotkeyRecorder.encode(modifiers: [.command], keyCode: 0xFFFF)
        #expect(s == nil)
    }
}
