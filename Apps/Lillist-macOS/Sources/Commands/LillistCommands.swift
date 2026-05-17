import SwiftUI
import AppKit
import LillistCore
import LillistUI

/// Commands wires the menu bar items and the keyboard shortcuts called out in
/// design Section 7. Each command posts a `Notification` that the relevant view
/// observes; this keeps the commands target-agnostic.
struct LillistCommands: Commands {
    let environment: AppEnvironment
    @FocusedValue(\.listColumn) private var listColumn: ListColumn?

    var body: some Commands {
        // Multi-window deferred — Plan 19 Task 3.
        // `CommandGroup(replacing: .newItem)` removed SwiftUI's implicit
        // ⌘N "New Window". Restoring it requires multi-window correctness
        // verification (independent RootSplitView state per window,
        // OnboardingPresentationModifier not re-firing on already-onboarded
        // users, focus-routing across windows). The shared `AppEnvironment`
        // pattern is Core-Data-safe, but the SwiftUI-state side needs an
        // eyeball pass that wasn't possible during Plan 19's autonomous
        // execution. Land ⌥⌘N "New Window" in a follow-up plan once the
        // verification can be driven interactively.
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                NotificationCenter.default.post(name: .lillistNewTask, object: nil)
            }.keyboardShortcut("n", modifiers: [.command])

            Button("New Sibling Task") {
                NotificationCenter.default.post(name: .lillistNewSibling, object: nil)
            }.keyboardShortcut(.return, modifiers: [.command, .shift])
        }

        CommandMenu("Task") {
            Button("Toggle Started") {
                NotificationCenter.default.post(name: .lillistToggleStarted, object: nil)
            }.keyboardShortcut(.space, modifiers: [])
              .disabled(listColumn == nil)

            Button("Mark Closed") {
                NotificationCenter.default.post(name: .lillistMarkClosed, object: nil)
            }.keyboardShortcut(.return, modifiers: [.command])
              .disabled(listColumn == nil)

            Button("Mark Blocked & Schedule Follow-up") {
                NotificationCenter.default.post(name: .lillistMarkBlocked, object: nil)
            }.keyboardShortcut(".", modifiers: [.command])
              .disabled(listColumn == nil)

            Divider()

            Button("Indent") {
                NotificationCenter.default.post(name: .lillistIndent, object: nil)
            }.keyboardShortcut(.tab, modifiers: [])
              .disabled(listColumn == nil)

            Button("Outdent") {
                NotificationCenter.default.post(name: .lillistOutdent, object: nil)
            }.keyboardShortcut(.tab, modifiers: [.shift])
              .disabled(listColumn == nil)
        }

        // Plan 15 Task 28: `replacing: .textEditing` destroyed the
        // standard Find submenu. Switch to `after:` so Find Next /
        // Find Previous / Use Selection for Find survive; ours append
        // below them.
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find in View…") {
                NotificationCenter.default.post(name: .lillistFindInView, object: nil)
            }.keyboardShortcut("f", modifiers: [.command])

            Button("Find Everywhere…") {
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

        // Plan 15 Task 29: ⌃⌘S toggles the sidebar (Mac convention,
        // matching Mail / Notes / Reminders). The toolbar button from
        // Task 1 also flips columnVisibility; this menu command goes
        // through a notification so the View has a single handler.
        CommandGroup(after: .sidebar) {
            Button("Show Sidebar") {
                NotificationCenter.default.post(name: .lillistToggleSidebar, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.control, .command])
        }

        // Plan 15 Task 21: custom About panel with byline credit.
        CommandGroup(replacing: .appInfo) {
            Button("About Lillist") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    .credits: NSAttributedString(
                        string: "Built by Mikey Ward",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                ])
            }
        }

        // Plan 15 Task 22: replace the default Help submenu with a
        // single Link to the repo. TODO: swap to a real docs site URL
        // once it exists.
        CommandGroup(replacing: .help) {
            Link("Lillist Help", destination: URL(string: "https://github.com/mikeydotio/Lillist")!)
        }
    }
}

extension Notification.Name {
    static let lillistNewTask           = Notification.Name("lillist.newTask")
    static let lillistNewSibling        = Notification.Name("lillist.newSibling")
    static let lillistToggleStarted     = Notification.Name("lillist.toggleStarted")
    static let lillistMarkClosed        = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked       = Notification.Name("lillist.markBlocked")
    static let lillistIndent            = Notification.Name("lillist.indent")
    static let lillistOutdent           = Notification.Name("lillist.outdent")
    static let lillistFindInView        = Notification.Name("lillist.findInView")
    static let lillistFindEverywhere    = Notification.Name("lillist.findEverywhere")
    static let lillistFocusSidebar      = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList         = Notification.Name("lillist.focusList")
    static let lillistFocusDetail       = Notification.Name("lillist.focusDetail")
    // Plan 15 Task 20: dock menu navigation.
    static let lillistSelectTodayFilter = Notification.Name("lillist.selectTodayFilter")
    static let lillistSelectFilter      = Notification.Name("lillist.selectFilter")
    // Plan 15 Task 29: ⌃⌘S menu command for sidebar visibility.
    static let lillistToggleSidebar     = Notification.Name("lillist.toggleSidebar")
    // Plan 19 Task 12: re-spawn the main window after ⌘W closed it (or
    // the menu-bar popover's "Show Main Window" button was clicked).
    static let lillistReopenMainWindow  = Notification.Name("lillist.reopenMainWindow")
}
