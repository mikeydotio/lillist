import LillistCore

/// Forward-only status progression driven by a tap/click on the status
/// indicator or the macOS keyboard status shortcut, per design Section 7.
///
/// - A tap advances `todo → started → closed`. `closed` is terminal: tapping a
///   done task is a no-op (`TaskStore.transition` short-circuits a same-status
///   transition), so the control never loops back past "done".
/// - `blocked` is only ever set via the right-click / long-press menu or the
///   ⌘. shortcut (which also reveals the follow-up form). Tapping a blocked
///   task advances it to `started` — "unblock and resume".
/// - Resetting a task back to `todo` lives elsewhere now: the "Mark open" swipe
///   on each platform's task rows, or the explicit menu setters.
public enum StatusCycler {
    public static func nextOnClick(from current: Status) -> Status {
        switch current {
        case .todo:    return .started
        case .started: return .closed
        case .blocked: return .started
        case .closed:  return .closed
        }
    }
}
