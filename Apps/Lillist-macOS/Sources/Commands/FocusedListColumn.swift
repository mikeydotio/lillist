import SwiftUI

/// Identifies which split-view column currently has keyboard focus.
/// Promoted to a top-level enum (originally `RootSplitView.Column`) so
/// the standalone macOS test bundle can reference it without
/// co-compiling RootSplitView and its `AppEnvironment` / sidebar
/// dependencies.
public enum ListColumn: Hashable, Sendable {
    case sidebar
    case list
    // `.detail` retired with the docked detail column (the unified editor is
    // a floating panel, not a focusable split-view column).
}

/// Single source of truth for whether the list-action keyboard
/// shortcuts (Space, Cmd-Return, Cmd-.) should be disabled. They fire
/// only when a list column holds focus; when no column is focused
/// (e.g. a TextField is first responder) they must be inert so typing
/// doesn't trigger them.
enum TaskListShortcutGate {
    static func isDisabled(listColumn: ListColumn?) -> Bool {
        listColumn == nil
    }
}

/// Published from `RootSplitView` so command-menu shortcuts can disable
/// themselves when no list column is focused (i.e. a TextField or other
/// first-responder is editing). Without this, raw shortcuts like Space,
/// ⌘D, ⌘., and Tab fire while the user is typing, trapping keys and
/// stealing system meanings.
///
/// Value is `nil` when no Lillist window is key or when focus has hopped
/// to a TextField (SwiftUI clears `@FocusState` in that case, which
/// propagates to a `nil` here via `.focusedValue(\.listColumn, …)`).
struct FocusedListColumnKey: FocusedValueKey {
    typealias Value = ListColumn
}

extension FocusedValues {
    var listColumn: ListColumn? {
        get { self[FocusedListColumnKey.self] }
        set { self[FocusedListColumnKey.self] = newValue }
    }
}
