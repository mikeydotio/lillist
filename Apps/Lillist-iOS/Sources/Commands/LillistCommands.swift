import SwiftUI
import LillistUI

/// Scene-level command surface. Exposes hardware-keyboard shortcuts to
/// the iPadOS hold-⌘ overlay (which only enumerates `CommandMenu` /
/// `CommandGroup` entries — not arbitrary `.keyboardShortcut` bindings
/// buried inside views).
///
/// Plan 16 replaces the previous hidden-Button hack in
/// `KeyboardShortcuts.swift`. `⌘N` previously bound to Quick Capture
/// collides with iPadOS's system "New Window" — moved to `⌘⇧N`.
///
/// Plan 20 Task 3 extends the surface with the status-mutation,
/// indent/outdent, and column-focus actions that already exist on
/// macOS so the iPad hardware-keyboard experience reaches parity.
/// Receivers for these notifications are out of scope here — adding
/// them lives with the future plan that wires the iPad shell to the
/// shared list/detail observers.
struct LillistCommands: Commands {
    @Binding var isQuickCapturePresented: Bool
    @Binding var selectedSection: iPadSection?

    var body: some Commands {
        CommandMenu("Lillist") {
            Button("New Task") {
                isQuickCapturePresented = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Today") { selectedSection = .today }
                .keyboardShortcut("1", modifiers: .command)
            Button("All") { selectedSection = .all }
                .keyboardShortcut("2", modifiers: .command)
            Button("Filters") { selectedSection = .filters }
                .keyboardShortcut("3", modifiers: .command)
            Button("Search") { selectedSection = .search }
                .keyboardShortcut("4", modifiers: .command)

            Divider()

            Button("Find in Lillist…") { selectedSection = .search }
                .keyboardShortcut("f", modifiers: [.command, .shift])
        }

        // Plan 20 Task 3: status-mutation and indent/outdent parity
        // with macOS. The actions post the same Notification.Name
        // values the macOS CommandMenu posts, so a future plan can
        // wire one shared observer in the list/detail view that
        // services both platforms.
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

        // Plan 20 Task 3: column-focus parity for the iPad three-column
        // split shell. ⌘1/2/3 here overlap with the compact-shell tab
        // shortcuts above; a future plan should gate this CommandMenu
        // on split-shell-active (either by plumbing a binding into
        // LillistCommands or by registering the shortcuts inside the
        // SplitShell view). Until then, both fire and the receiver
        // discriminates by context (compact ignores focus posts;
        // split shell ignores tab section changes).
        CommandMenu("View") {
            Button("Focus Sidebar") {
                NotificationCenter.default.post(name: .lillistFocusSidebar, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Focus List") {
                NotificationCenter.default.post(name: .lillistFocusList, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Focus Detail") {
                NotificationCenter.default.post(name: .lillistFocusDetail, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    // Mirror the macOS LillistCommands names so a future shared
    // observer can listen on a single name regardless of platform.
    static let lillistMarkClosed   = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked  = Notification.Name("lillist.markBlocked")
    static let lillistIndent       = Notification.Name("lillist.indent")
    static let lillistOutdent      = Notification.Name("lillist.outdent")
    static let lillistFocusSidebar = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList    = Notification.Name("lillist.focusList")
    static let lillistFocusDetail  = Notification.Name("lillist.focusDetail")
}
