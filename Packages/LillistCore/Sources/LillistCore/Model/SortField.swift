import Foundation

/// Available sort fields for task lists.
///
/// `manualPosition` only makes sense within a single parent. Smart filter
/// results spanning multiple parents must use another sort field; the
/// `*Store` layer rejects `manualPosition` with `LillistError.validationFailed`
/// when the query crosses parent boundaries.
public enum SortField: String, CaseIterable, Codable, Sendable {
    case manualPosition
    case start
    case deadline
    case title
    case createdAt
    case modifiedAt
    case closedAt
    case status
}

extension SortField {
    /// Whether this sort field's underlying key is left untouched by a status
    /// transition. `modifiedAt` (bumped on every mutation) and `status`
    /// (`statusRaw`) both change when a task is merely advanced, so ordering an
    /// open list by them makes rows jump on a status tap; every other field is
    /// invariant under `TaskStore.transition`. The widget uses this to keep
    /// in-progress rows in place (see ``WidgetSnapshotBuilder``).
    public var isStableUnderStatusTransition: Bool {
        self != .modifiedAt && self != .status
    }
}
