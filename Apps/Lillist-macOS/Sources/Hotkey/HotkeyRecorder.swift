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
                Text(recording ? "Press a key combination…" : displayString)
                    .font(.system(.body, design: .monospaced))
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

    private var displayString: String {
        value.isEmpty ? "—" : value
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
    static func encode(modifiers: NSEvent.ModifierFlags, keyCode: Int) -> String? {
        // Canonical order, derived from Plan 11 Task 17's encoder
        // contract tests: `ctrl, opt, cmd, shift, <key>`. (Both
        // `ctrl+opt+space` and `cmd+shift+l` must round-trip cleanly.)
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
    private static func keyName(for keyCode: Int) -> String? {
        HotkeyKeyTable.name(forKeyCode: keyCode)
    }
}
