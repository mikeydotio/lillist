import Foundation

/// Canonical mapping between macOS virtual key codes and the
/// lowercase string tokens used in user-facing hotkey combos
/// (`ctrl+opt+space`, `cmd+shift+l`).
///
/// Single source of truth: both ``HotkeyRecorder.encode`` (keyCode →
/// name, for writing user combos to preferences) and
/// ``GlobalHotkeyMonitor.parse`` (name → keyCode, for arming the
/// matcher) call through this enum. Plan 12 collapsed the two
/// previously-duplicated tables — adding a key in one place without
/// the other used to cause silent round-trip failures.
enum HotkeyKeyTable {
    /// Lookup keyed by macOS virtual key code; returns the canonical
    /// lowercase token, or `nil` for keys that aren't user-bindable.
    static func name(forKeyCode keyCode: Int) -> String? {
        codeToName[keyCode]
    }

    /// Lookup keyed by lowercase token; returns the macOS virtual key
    /// code, or `nil` for unknown names.
    static func keyCode(forName name: String) -> Int? {
        nameToCode[name]
    }

    /// Master table. Edits here automatically update both lookup
    /// directions and stay in sync.
    private static let entries: [(keyCode: Int, name: String)] = [
        // Letters
        (0, "a"), (1, "s"), (2, "d"), (3, "f"),
        (4, "h"), (5, "g"), (6, "z"), (7, "x"),
        (8, "c"), (9, "v"), (11, "b"), (12, "q"),
        (13, "w"), (14, "e"), (15, "r"), (16, "y"),
        (17, "t"), (31, "o"), (32, "u"), (34, "i"),
        (35, "p"), (37, "l"), (38, "j"), (40, "k"),
        (45, "n"), (46, "m"),
        // Whitespace & navigation
        (49, "space"), (36, "return"), (51, "delete"), (53, "escape"),
        // Digits
        (18, "1"), (19, "2"), (20, "3"), (21, "4"),
        (23, "5"), (22, "6"), (26, "7"), (28, "8"),
        (25, "9"), (29, "0"),
        // Function keys
        (122, "f1"), (120, "f2"), (99, "f3"), (118, "f4"),
        (96, "f5"), (97, "f6"), (98, "f7"), (100, "f8"),
        (101, "f9"), (109, "f10"), (103, "f11"), (111, "f12")
    ]

    private static let codeToName: [Int: String] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.keyCode, $0.name) }
    )
    private static let nameToCode: [String: Int] = Dictionary(
        uniqueKeysWithValues: entries.map { ($0.name, $0.keyCode) }
    )
}
