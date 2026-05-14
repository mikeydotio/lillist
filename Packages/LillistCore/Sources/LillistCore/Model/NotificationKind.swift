import Foundation

/// Kinds of `NotificationSpec`, matching the four-layer delivery model in
/// design Section 4.
///
/// Raw values are persisted; never reorder or remove cases. New kinds must
/// take an unused raw value. Stored in Core Data as `Int16`.
public enum NotificationKind: Int, CaseIterable, Codable, Sendable {
    /// Layer 1/2 auto-spec keyed off `LillistTask.start`.
    case defaultStart = 0
    /// Layer 1/2 auto-spec keyed off `LillistTask.deadline`.
    case defaultDeadline = 1
    /// Layer 3 user-added offset relative to `start`.
    case offsetStart = 2
    /// Layer 3 user-added offset relative to `deadline`.
    case offsetDeadline = 3
    /// Independent absolute-date nudge.
    case nudge = 4

    /// Which task field this kind is anchored to, or `nil` for nudges (which
    /// carry their own absolute `fireDate`).
    public enum Anchor: Sendable {
        case start
        case deadline
    }

    public var anchor: Anchor? {
        switch self {
        case .defaultStart, .offsetStart: return .start
        case .defaultDeadline, .offsetDeadline: return .deadline
        case .nudge: return nil
        }
    }

    public var isOffset: Bool {
        self == .offsetStart || self == .offsetDeadline
    }
}
