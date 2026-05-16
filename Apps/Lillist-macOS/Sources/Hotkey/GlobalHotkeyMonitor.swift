import AppKit

/// Listens for the user-configured Quick Capture hotkey system-wide.
///
/// The default combo is ⌃⌥Space, but Plan 11 Task 18 generalizes the
/// monitor so that any combo string produced by ``HotkeyRecorder.encode``
/// can be installed (and *re-installed*) at runtime. Falls back
/// gracefully if Accessibility permission has not been granted: the
/// user sees a prompt on first install.
@MainActor
final class GlobalHotkeyMonitor {
    /// Default combo used when neither the constructor nor ``install``
    /// is supplied an explicit combo string. Mirrors the
    /// `PreferencesStore` default.
    static let defaultCombo: String = "ctrl+opt+space"

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// The combo currently armed in `matchesHotkey`. Parsed once on
    /// install / re-register and cached so the per-keystroke matcher
    /// stays branch-free.
    private var armedModifiers: NSEvent.ModifierFlags = [.control, .option]
    private var armedKeyCode: Int = 49 // space

    /// Invoked on the main actor whenever the armed combo fires. The
    /// caller is expected to bounce work onto whichever actor it needs
    /// — this monitor only routes the trigger.
    var onHotkey: () -> Void = {}

    init(initialCombo: String = GlobalHotkeyMonitor.defaultCombo) {
        if let parsed = Self.parse(combo: initialCombo) {
            self.armedModifiers = parsed.modifiers
            self.armedKeyCode = parsed.keyCode
        }
    }

    /// Install both the global and local NSEvent monitors using the
    /// combo previously configured by ``init(initialCombo:)`` or the
    /// most recent ``reregister(combo:)`` call. Idempotent: if the
    /// monitors are already installed they are torn down first so the
    /// fresh tokens reflect the current combo.
    func install() {
        uninstall()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if self.matchesHotkey(event) { Task { @MainActor in self.onHotkey() } }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.matchesHotkey(event) {
                Task { @MainActor in self.onHotkey() }
                return nil
            }
            return event
        }
    }

    func uninstall() {
        if let g = globalMonitor { NSEvent.removeMonitor(g) }
        if let l = localMonitor  { NSEvent.removeMonitor(l) }
        globalMonitor = nil; localMonitor = nil
    }

    /// Re-install the global hotkey with a new combo string. Called from
    /// the Quick Capture preferences pane after the user saves a new
    /// combo. Idempotent: calling with the same combo is safe to re-run.
    ///
    /// Unparseable combos are ignored (the previously armed combo stays
    /// in effect). This matches `HotkeyRecorder.encode`'s contract of
    /// returning `nil` for unsupported keys: the recorder won't write
    /// such strings into the store in the first place, but we defend
    /// against malformed user-edited preferences too.
    public func reregister(combo: String) {
        guard let parsed = Self.parse(combo: combo) else { return }
        armedModifiers = parsed.modifiers
        armedKeyCode = parsed.keyCode
        // install() handles teardown + reinstall in one shot.
        install()
    }

    /// Matches the supplied keystroke against the armed combo. Modifier
    /// equality uses `deviceIndependentFlagsMask` so caps-lock and the
    /// numeric-pad sentinel bit don't poison the comparison.
    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return Int(event.keyCode) == armedKeyCode && actual == armedModifiers
    }

    // MARK: - Pure parser (inverse of HotkeyRecorder.encode)

    /// Parses a canonical combo string (e.g. `"ctrl+opt+space"`,
    /// `"cmd+shift+l"`) into a `(modifiers, keyCode)` pair. Returns
    /// `nil` if the string is empty, the trailing token isn't a known
    /// key name, or any non-trailing token isn't a known modifier
    /// (`ctrl`, `opt`, `cmd`, `shift`).
    ///
    /// Order-tolerant on read: while ``HotkeyRecorder.encode`` always
    /// emits modifiers in `ctrl, opt, cmd, shift` order, the parser
    /// accepts any modifier ordering so manually-edited preferences
    /// still round-trip.
    static func parse(combo: String) -> (modifiers: NSEvent.ModifierFlags, keyCode: Int)? {
        let tokens = combo.split(separator: "+").map { String($0).lowercased() }
        guard let keyToken = tokens.last, tokens.count >= 1 else { return nil }
        guard let keyCode = keyCode(for: keyToken) else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        for token in tokens.dropLast() {
            switch token {
            case "ctrl":  modifiers.insert(.control)
            case "opt":   modifiers.insert(.option)
            case "cmd":   modifiers.insert(.command)
            case "shift": modifiers.insert(.shift)
            default: return nil
            }
        }
        return (modifiers, keyCode)
    }

    /// Maps a canonical key-name token to its macOS virtual key code.
    /// This is the inverse of ``HotkeyRecorder.keyName(for:)`` and must
    /// stay in sync with it.
    private static func keyCode(for name: String) -> Int? {
        switch name {
        case "a": return 0;  case "s": return 1;  case "d": return 2;  case "f": return 3
        case "h": return 4;  case "g": return 5;  case "z": return 6;  case "x": return 7
        case "c": return 8;  case "v": return 9;  case "b": return 11; case "q": return 12
        case "w": return 13; case "e": return 14; case "r": return 15; case "y": return 16
        case "t": return 17; case "o": return 31; case "u": return 32; case "i": return 34
        case "p": return 35; case "l": return 37; case "j": return 38; case "k": return 40
        case "n": return 45; case "m": return 46; case "space": return 49
        case "return": return 36; case "delete": return 51; case "escape": return 53
        case "1": return 18; case "2": return 19; case "3": return 20; case "4": return 21
        case "5": return 23; case "6": return 22; case "7": return 26; case "8": return 28
        case "9": return 25; case "0": return 29
        case "f1": return 122; case "f2": return 120; case "f3": return 99;  case "f4": return 118
        case "f5": return 96;  case "f6": return 97;  case "f7": return 98;  case "f8": return 100
        case "f9": return 101; case "f10": return 109; case "f11": return 103; case "f12": return 111
        default: return nil
        }
    }
}
