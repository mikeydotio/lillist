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
