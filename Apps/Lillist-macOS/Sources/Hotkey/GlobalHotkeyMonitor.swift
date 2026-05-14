import AppKit

/// Listens for ⌃⌥Space system-wide. Falls back gracefully if Accessibility
/// permission has not been granted: the user sees a prompt on first install.
@MainActor
final class GlobalHotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var onHotkey: () -> Void = {}

    func install() {
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

    /// ⌃⌥Space — control + option + space (key code 49).
    private func matchesHotkey(_ event: NSEvent) -> Bool {
        let needed: NSEvent.ModifierFlags = [.control, .option]
        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49 && actual == needed
    }
}
