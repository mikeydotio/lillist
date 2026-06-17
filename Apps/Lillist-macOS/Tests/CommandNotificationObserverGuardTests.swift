import XCTest
import Foundation

/// Guard against re-introducing dead menu commands: every notification
/// name the `LillistCommands` menu posts must have a live observer (be in
/// the curated `observed` set below). `macos-2` shipped four commands
/// (Indent / Outdent / Find in View / Find Everywhere) that posted into
/// the void; this fails if any such name reappears unobserved.
///
/// `observed` is maintained by hand from the real `.onReceive` /
/// `addObserver` sites: RootSplitView, TaskListView, AppDelegate,
/// LillistApp, MenuBarExtraScene. When you add a command, add its
/// observer AND list it here — or the build fails.
final class CommandNotificationObserverGuardTests: XCTestCase {
    private let observed: Set<Notification.Name> = [
        .lillistNewTask,
        .lillistNewSibling,
        .lillistToggleStarted,
        .lillistMarkClosed,
        .lillistMarkBlocked,
        .lillistFocusSidebar,
        .lillistFocusList,
        .lillistOpenTaskEditor,
        .lillistToggleSidebar,
        .lillistSelectTodayFilter,
        .lillistSelectFilter,
        .lillistReopenMainWindow
    ]

    func test_everyPostedCommandNotificationHasAnObserver() {
        let posted = Set(CommandNotifications.postedByCommands)
        let unobserved = posted.subtracting(observed)
        XCTAssertTrue(
            unobserved.isEmpty,
            "These command notifications are posted but unobserved (dead menu commands): \(unobserved.map(\.rawValue).sorted())"
        )
    }

    func test_theFourKnownDeadNamesAreGone() {
        let posted = Set(CommandNotifications.postedByCommands)
        for raw in ["lillist.indent", "lillist.outdent", "lillist.findInView", "lillist.findEverywhere"] {
            XCTAssertFalse(
                posted.contains(Notification.Name(raw)),
                "\(raw) was a dead command removed in macos-2; do not reintroduce it without an observer"
            )
        }
    }
}
