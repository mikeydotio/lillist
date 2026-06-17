import Foundation

/// What the unified editor panel should do for an open request, given whether
/// one is already showing. Pure value-math so the singleton rules are
/// unit-tested without a live `NSPanel`.
///
/// - A quick-capture request (global hotkey / ⌘-capture) is a **no-op while the
///   panel is already open** (the hotkey doesn't dismiss or stack).
/// - An existing-task request **re-targets** an already-open panel to the new
///   task instead of spawning a second one.
enum EditorOpenRequest: Equatable {
    case quickCapture
    case existing(UUID)
}

enum EditorOpenDecision: Equatable {
    /// Present a fresh panel for the request.
    case present(EditorOpenRequest)
    /// Re-target the open panel to this task.
    case retarget(UUID)
    /// Do nothing (hotkey while already open).
    case noop

    static func decide(isOpen: Bool, request: EditorOpenRequest) -> EditorOpenDecision {
        switch request {
        case .quickCapture:
            return isOpen ? .noop : .present(.quickCapture)
        case .existing(let id):
            return isOpen ? .retarget(id) : .present(.existing(id))
        }
    }
}
