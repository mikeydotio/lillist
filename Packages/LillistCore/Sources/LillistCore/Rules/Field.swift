import Foundation

/// Every queryable field on a task, per design Section 5.
///
/// Raw values are stable strings used in JSON serialization and CLI argument
/// parsing. Reordering or removing cases is a breaking change.
public enum Field: String, CaseIterable, Codable, Sendable {
    case title
    case notes
    case journalText
    case tag
    case status
    case start
    case deadline
    case createdAt
    case modifiedAt
    case closedAt
    case hasAttachments
    case hasChildren
    case hasNudges
    case isPinned
    case ancestor
    case recurrence
    case inTrash
}
