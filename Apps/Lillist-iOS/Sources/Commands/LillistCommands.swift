import SwiftUI
import LillistUI

/// Scene-level command surface. Exposes hardware-keyboard shortcuts to
/// the iPadOS hold-⌘ overlay (which only enumerates `CommandMenu` /
/// `CommandGroup` entries — not arbitrary `.keyboardShortcut` bindings
/// buried inside views).
///
/// The 3-tab restructure collapsed the previous section/search command
/// surface into a single primary `TasksView`, so the previous
/// `Today/All/Filters` and `Find in Lillist…` shortcuts are gone.
/// `⌘⇧N` still binds Quick Capture (avoiding the iPadOS-reserved `⌘N`).
/// The status-mutation and indent/outdent shortcuts remain, posting
/// notifications for the list/detail surfaces to observe.
struct LillistCommands: Commands {
    @Binding var isQuickCapturePresented: Bool

    var body: some Commands {
        CommandMenu("Lillist") {
            Button("New Task") {
                isQuickCapturePresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Task") {
            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }
            .keyboardShortcut(".", modifiers: [.command])

            Divider()

            // ⌘⇧J / ⌘⇧K instead of macOS's Tab / Shift-Tab because
            // iPadOS reserves Tab for system focus navigation.
            Button("Indent") {
                NotificationCenter.default.post(name: .lillistIndent, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("Outdent") {
                NotificationCenter.default.post(name: .lillistOutdent, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}

extension Notification.Name {
    static let lillistMarkClosed   = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked  = Notification.Name("lillist.markBlocked")
    static let lillistIndent       = Notification.Name("lillist.indent")
    static let lillistOutdent      = Notification.Name("lillist.outdent")
    static let lillistFocusSidebar = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList    = Notification.Name("lillist.focusList")
    static let lillistFocusDetail  = Notification.Name("lillist.focusDetail")
}
