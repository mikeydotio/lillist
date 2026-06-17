import Foundation

/// Command-menu notification names, promoted out of `LillistCommands`
/// into a dependency-free file so the standalone `Lillist-macOSTests`
/// bundle can co-compile it without `@testable import Lillist_macOS`
/// (it has no app test host). Mirrors the `FocusedListColumn.swift`
/// extraction pattern.
extension Notification.Name {
    static let lillistNewTask           = Notification.Name("lillist.newTask")
    static let lillistNewSibling        = Notification.Name("lillist.newSibling")
    static let lillistToggleStarted     = Notification.Name("lillist.toggleStarted")
    static let lillistMarkClosed        = Notification.Name("lillist.markClosed")
    static let lillistMarkBlocked       = Notification.Name("lillist.markBlocked")
    static let lillistFocusSidebar      = Notification.Name("lillist.focusSidebar")
    static let lillistFocusList         = Notification.Name("lillist.focusList")
    // Open the unified task editor for the focused list's selected task
    // (keyboard "Open Task" command; row clicks use the env action). Replaces
    // the retired `lillistFocusDetail` (the detail column is gone).
    static let lillistOpenTaskEditor    = Notification.Name("lillist.openTaskEditor")
    // Posted by the editor panel on close so the list refreshes its rows.
    // NOT a command-menu post — excluded from `postedByCommands`.
    static let lillistTasksDidChange    = Notification.Name("lillist.tasksDidChange")
    // Plan 15 Task 20: dock menu navigation.
    static let lillistSelectTodayFilter = Notification.Name("lillist.selectTodayFilter")
    static let lillistSelectFilter      = Notification.Name("lillist.selectFilter")
    // Plan 15 Task 29: ⌃⌘S menu command for sidebar visibility.
    static let lillistToggleSidebar     = Notification.Name("lillist.toggleSidebar")
    // Plan 19 Task 12: re-spawn the main window after ⌘W closed it (or
    // the menu-bar popover's "Show Main Window" button was clicked).
    static let lillistReopenMainWindow  = Notification.Name("lillist.reopenMainWindow")
}

/// Registry of every notification the `LillistCommands` menu surface
/// posts. `CommandNotificationObserverGuardTests` asserts each one has a
/// live observer, so a re-introduced dead command fails the build. Keep
/// this in sync when adding/removing a posting button.
enum CommandNotifications {
    static let postedByCommands: [Notification.Name] = [
        .lillistNewTask,
        .lillistNewSibling,
        .lillistToggleStarted,
        .lillistMarkClosed,
        .lillistMarkBlocked,
        .lillistFocusSidebar,
        .lillistFocusList,
        .lillistOpenTaskEditor,
        .lillistToggleSidebar
    ]
}
