import Foundation

/// One entry in the breadcrumb ring buffer.
///
/// By contract, `action` is a verb-form string (e.g. `"task.create"`)
/// and contains no titles, IDs, paths, or email addresses. See design
/// Section 8: "no titles or content, just verbs and counts."
public struct Breadcrumb: Codable, Equatable, Sendable {
    public let action: String
    public let at: Date
    public let success: Bool

    public init(action: String, at: Date, success: Bool) {
        self.action = action
        self.at = at
        self.success = success
    }
}
