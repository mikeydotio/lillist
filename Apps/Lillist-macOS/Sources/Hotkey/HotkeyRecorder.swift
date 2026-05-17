import SwiftUI
import AppKit

/// SwiftUI view that captures a single keystroke (with modifiers) and
/// updates its bound value with the canonical string format used by
/// `GlobalHotkeyMonitor` (e.g. `"ctrl+opt+space"`, `"cmd+shift+l"`).
///
/// Plan 11 Task 17 replaces the Plan 10 plain-text-field placeholder.
/// The recorder uses `NSEvent.addLocalMonitorForEvents(matching:.keyDown)`
/// while in recording mode, swallows the captured event, and writes the
/// encoded combination into the supplied `@Binding`. The pure
/// ``encode(modifiers:keyCode:)`` static helper is what the Quick
/// Capture preferences pane and the standalone test bundle exercise.
struct HotkeyRecorder: View {
    @Binding var value: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    recording ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
            HStack {
                if recording {
                    Text("Press a key combination…")
                        .foregroundStyle(.secondary)
                } else {
                    glyphRow
                }
                Spacer()
                Button(recording ? "Stop" : "Record") {
                    toggleRecording()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 28)
    }

    /// SF-Symbol-based render of the current `value`. Falls back to the
    /// raw string ("—" for empty) if the value can't be parsed by
    /// `GlobalHotkeyMonitor.parse`. The display agrees with the system
    /// Settings → Keyboard Shortcuts pane (⌃⌥⇧⌘ + key cap).
    @ViewBuilder
    private var glyphRow: some View {
        if value.isEmpty {
            Text("—").foregroundStyle(.secondary)
        } else {
            let tokens = value.split(separator: "+").map { String($0).lowercased() }
            HStack(spacing: 2) {
                ForEach(tokens.dropLast(), id: \.self) { mod in
                    Image(systemName: Self.symbolName(forModifier: mod))
                        .accessibilityHidden(true)
                }
                if let key = tokens.last {
                    KeyCap(label: Self.keyCapLabel(for: key))
                }
            }
            .accessibilityLabel(Self.accessibilityDescription(for: tokens))
        }
    }

    /// SF Symbol name for a modifier token. Mirrors the canonical
    /// tokens emitted by `encode(modifiers:keyCode:)`.
    nonisolated private static func symbolName(forModifier token: String) -> String {
        switch token {
        case "ctrl":  return "control"
        case "opt":   return "option"
        case "cmd":   return "command"
        case "shift": return "shift"
        default:      return "questionmark"
        }
    }

    /// Friendly label for the key glyph inside a `KeyCap`. Most letters
    /// render uppercase; whitespace and navigation keys spell out
    /// (`space`, `return`, `delete`, `escape`); function keys keep
    /// their `F1` form.
    nonisolated private static func keyCapLabel(for token: String) -> String {
        switch token {
        case "space":  return "space"
        case "return": return "↩"
        case "delete": return "⌫"
        case "escape": return "esc"
        default:       return token.uppercased()
        }
    }

    nonisolated private static func accessibilityDescription(for tokens: [String]) -> String {
        let mods = tokens.dropLast().map { friendlyModifier($0) }
        let key = tokens.last.map { friendlyKey($0) } ?? "no key"
        return (mods + [key]).joined(separator: " ")
    }

    nonisolated private static func friendlyModifier(_ token: String) -> String {
        switch token {
        case "ctrl":  return "Control"
        case "opt":   return "Option"
        case "cmd":   return "Command"
        case "shift": return "Shift"
        default:      return token
        }
    }

    nonisolated private static func friendlyKey(_ token: String) -> String {
        switch token {
        case "space":  return "Space"
        case "return": return "Return"
        case "delete": return "Delete"
        case "escape": return "Escape"
        default:       return token.uppercased()
        }
    }

    private func toggleRecording() {
        if recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let encoded = HotkeyRecorder.encode(
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                keyCode: Int(event.keyCode)
            )
            if let encoded {
                value = encoded
                stopRecording()
            }
            return nil // swallow the event
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    // MARK: - Pure encoder (testable)

    /// Encodes a modifier-flag set + key-code pair into the canonical
    /// `"ctrl+opt+shift+cmd+<key>"` string that `GlobalHotkeyMonitor`
    /// parses. Returns `nil` for key codes that aren't in the supported
    /// alphanumeric / function / control-key set; callers should keep
    /// listening in that case.
    nonisolated static func encode(modifiers: NSEvent.ModifierFlags, keyCode: Int) -> String? {
        // Canonical order, derived from Plan 11 Task 17's encoder
        // contract tests: `ctrl, opt, cmd, shift, <key>`. (Both
        // `ctrl+opt+space` and `cmd+shift+l` must round-trip cleanly.)
        // `nonisolated` because the encoder is a pure function over
        // `HotkeyKeyTable` (a plain enum) and shouldn't inherit
        // `View`'s `@MainActor` isolation.
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.shift) { parts.append("shift") }
        guard let keyName = keyName(for: keyCode) else { return nil }
        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    /// Maps a macOS virtual key code to the string token used in the
    /// canonical hotkey representation. Covers letters, digits, F1–F12,
    /// space, return, delete, and escape — the keys most users will
    /// bind to a global hotkey. Extend as needed.
    nonisolated private static func keyName(for keyCode: Int) -> String? {
        HotkeyKeyTable.name(forKeyCode: keyCode)
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 0.5)
                    )
            )
    }
}
