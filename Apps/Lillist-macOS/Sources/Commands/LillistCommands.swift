import SwiftUI
import LillistCore
import LillistUI

/// Commands wires the menu bar items and the keyboard shortcuts called out in
/// design Section 7. Each command posts a `Notification` that the relevant view
/// observes; this keeps the commands target-agnostic.
struct LillistCommands: Commands {
    let environment: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                NotificationCenter.default.post(name: .lillistNewTask, object: nil)
            }.keyboardShortcut("n", modifiers: [.command])

            Button("New Sibling Task") {
                NotificationCenter.default.post(name: .lillistNewSibling, object: nil)
            }.keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Task") {
            Button("Toggle Started") {
                NotificationCenter.default.post(name: .lillistToggleStarted, object: nil)
            }.keyboardShortcut(.space, modifiers: [])

            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }.keyboardShortcut("d", modifiers: [.command])

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }.keyboardShortcut(".", modifiers: [.command])

            Divider()

            Button("Indent") {
                NotificationCenter.default.post(name: .lillistIndent, object: nil)
            }.keyboardShortcut(.tab, modifiers: [])

            Button("Outdent") {
                NotificationCenter.default.post(name: .lillistOutdent, object: nil)
            }.keyboardShortcut(.tab, modifiers: [.shift])
        }

        CommandGroup(replacing: .textEditing) {
            Button("Find in View") {
                NotificationCenter.default.post(name: .lillistFindInView, object: nil)
            }.keyboardShortcut("f", modifiers: [.command])

            Button("Find Everywhere") {
                NotificationCenter.default.post(name: .lillistFindEverywhere, object: nil)
            }.keyboardShortcut("f", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Focus Sidebar") {
                NotificationCenter.default.post(name: .lillistFocusSidebar, object: nil)
            }.keyboardShortcut("1", modifiers: [.command])
            Button("Focus List") {
                NotificationCenter.default.post(name: .lillistFocusList, object: nil)
            }.keyboardShortcut("2", modifiers: [.command])
            Button("Focus Detail") {
                NotificationCenter.default.post(name: .lillistFocusDetail, object: nil)
            }.keyboardShortcut("3", modifiers: [.command])
        }
    }
}

extension Notification.Name {
    static let lillistNewTask         = Notification.Name("lillist.newTask")
    static let lillistNewSibling      = Notification.Name("lillist.newSibling")
    static let lillistToggleStarted   = Notification.Name("lillist.toggleStarted")
    static let lillistMarkClosed      = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked     = Notification.Name("lillist.markBlocked")
    static let lillistIndent          = Notification.Name("lillist.indent")
    static let lillistOutdent         = Notification.Name("lillist.outdent")
    static let lillistFindInView      = Notification.Name("lillist.findInView")
    static let lillistFindEverywhere  = Notification.Name("lillist.findEverywhere")
    static let lillistFocusSidebar    = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList       = Notification.Name("lillist.focusList")
    static let lillistFocusDetail     = Notification.Name("lillist.focusDetail")
}
