import LillistCore

/// State machine for status transitions driven by UI gestures, per design Section 7.
///
/// - Click on the status indicator cycles todo → started → closed → todo.
///   Blocked is intentionally unreachable by click; it requires the right-click
///   menu or the ⌘. keyboard shortcut (which also reveals the follow-up form).
/// - Space toggles to/from `.started` from any state.
public enum StatusCycler {
    public static func nextOnClick(from current: Status) -> Status {
        switch current {
        case .todo:    return .started
        case .started: return .closed
        case .closed:  return .todo
        case .blocked: return .todo
        }
    }

    public static func nextOnSpace(from current: Status) -> Status {
        current == .started ? .todo : .started
    }
}
