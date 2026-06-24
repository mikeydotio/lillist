import Foundation

/// Notification names used by the macOS app shell, promoted out of
/// `LillistCommands` into a dependency-free file so the standalone
/// `Lillist-macOSTests` bundle can co-compile it without
/// `@testable import Lillist_macOS` (it has no app test host).
///
/// After the single-column main window adopted the shared iOS UI, the
/// menu surface no longer posts any notifications (⌘N flips a binding;
/// the selection/sidebar commands were retired). The remaining names are
/// posted by the AppDelegate Dock menu, the menu-bar extra, and the
/// global-hotkey editor panel — all observed by `MacTasksView` /
/// `LillistApp`.
extension Notification.Name {
    // Posted by the global-hotkey editor panel on close so the list
    // refreshes its rows. Observed by `MacTasksView`.
    static let lillistTasksDidChange    = Notification.Name("lillist.tasksDidChange")
    // Dock menu navigation → focus the Today chip / select a saved filter.
    // Observed by `MacTasksView`.
    static let lillistSelectTodayFilter = Notification.Name("lillist.selectTodayFilter")
    static let lillistSelectFilter      = Notification.Name("lillist.selectFilter")
    // Re-spawn the main window after ⌘W closed it (or the menu-bar
    // popover's "Show Main Window" button). Observed by `LillistApp`.
    static let lillistReopenMainWindow  = Notification.Name("lillist.reopenMainWindow")
}

/// Registry of every notification the `LillistCommands` menu surface
/// posts. `CommandNotificationObserverGuardTests` asserts each one has a
/// live observer, so a re-introduced dead command fails the build. The
/// menu currently posts nothing (⌘N flips a binding), so this is empty —
/// keep it in sync when adding a posting menu button.
enum CommandNotifications {
    static let postedByCommands: [Notification.Name] = []
}
