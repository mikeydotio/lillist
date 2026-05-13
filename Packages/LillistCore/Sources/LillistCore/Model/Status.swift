import Foundation

/// The lifecycle state of a task.
///
/// Raw values are persisted; never reorder or remove cases. New statuses
/// must take an unused raw value. Stored in Core Data as `Int16`.
public enum Status: Int, CaseIterable, Codable, Sendable {
    case todo = 0
    case started = 1
    case blocked = 2
    case closed = 3

    /// True if this status represents a completed/terminal state.
    public var isClosed: Bool {
        self == .closed
    }
}
