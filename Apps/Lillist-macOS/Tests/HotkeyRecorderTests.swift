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
        // Use a multi-modifier combo so the Plan 15 Task 18 bare-Cmd
        // guard doesn't short-circuit; we want to assert the
        // unknown-keyCode branch specifically.
        let s = HotkeyRecorder.encode(modifiers: [.control, .option], keyCode: 0xFFFF)
        #expect(s == nil)
    }

    /// Plan 12 Task 4 — guard the encoder/parser pair against silent
    /// divergence. `HotkeyRecorder.encode` and `GlobalHotkeyMonitor.parse`
    /// must agree on every (modifiers, keyCode) pair the recorder is
    /// allowed to emit; otherwise a user-recorded combo would fail to
    /// re-arm the global monitor after the app relaunches.
    ///
    /// `GlobalHotkeyMonitor` is `@MainActor`-isolated (it touches
    /// `NSEvent` global monitors), so its `static parse` inherits main-
    /// actor isolation — hence the `@MainActor` annotation on this test.
    @MainActor
    @Test("Encode then parse round-trips for representative combos")
    func encodeParseRoundTrip() {
        // Plan 15 Task 18 added a guard rejecting modifier sets that
        // lack ⌃/⌥/⇧ (so `cmd+1` is no longer encodable). The
        // round-trip cases below all carry at least one of those
        // modifiers and remain valid.
        let cases: [(modifiers: NSEvent.ModifierFlags, keyCode: Int)] = [
            ([.control, .option], 49),         // ctrl+opt+space (default)
            ([.command, .shift], 37),          // cmd+shift+l
            ([.command, .option, .shift], 99), // cmd+opt+shift+f3
            ([.shift], 122)                    // shift+f1
        ]
        for c in cases {
            guard let encoded = HotkeyRecorder.encode(modifiers: c.modifiers, keyCode: c.keyCode) else {
                Issue.record("encode returned nil for \(c)")
                continue
            }
            guard let parsed = GlobalHotkeyMonitor.parse(combo: encoded) else {
                Issue.record("parse returned nil for '\(encoded)'")
                continue
            }
            #expect(parsed.modifiers == c.modifiers, "modifiers diverged for '\(encoded)'")
            #expect(parsed.keyCode == c.keyCode, "keyCode diverged for '\(encoded)'")
        }
    }
}
