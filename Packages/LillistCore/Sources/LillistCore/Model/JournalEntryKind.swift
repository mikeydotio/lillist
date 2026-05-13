import Foundation

public enum JournalEntryKind: Int, CaseIterable, Codable, Sendable {
    case note = 0
    case statusChange = 1
    case attachment = 2
    case createdFollowUp = 3

    /// System-generated entries (status changes, follow-up creation)
    /// have their body managed by the app and reject user edits.
    public var isUserEditable: Bool {
        switch self {
        case .note, .attachment:
            return true
        case .statusChange, .createdFollowUp:
            return false
        }
    }
}
