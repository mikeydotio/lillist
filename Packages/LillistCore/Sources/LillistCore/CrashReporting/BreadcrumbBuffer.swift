import Foundation

/// Thread-safe ring buffer of the last 200 user actions.
///
/// The buffer's job is to capture **what** happened (verb), **when**
/// (timestamp), and **whether it succeeded** — but never anything
/// that could identify the data the user was operating on. Inputs
/// containing UUIDs, paths, or email addresses are rejected at the
/// API boundary; see design Section 8.
public actor BreadcrumbBuffer {
    /// Maximum number of entries retained. Per design Section 8.
    public static let capacity: Int = 200

    private var entries: [Breadcrumb] = []

    public init() {}

    public enum RecordError: Error, Equatable, Sendable {
        case containsUUID
        case containsEmail
        case containsPath
        case empty
    }

    /// Record an action. Throws if the action string appears to
    /// contain identifying content.
    public func record(action: String, success: Bool, at: Date = .now) throws {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecordError.empty }
        if Self.uuidRegex.firstMatch(
            in: action,
            range: NSRange(action.startIndex..., in: action)
        ) != nil {
            throw RecordError.containsUUID
        }
        if action.contains("@") {
            throw RecordError.containsEmail
        }
        if action.contains("/") {
            throw RecordError.containsPath
        }
        entries.append(Breadcrumb(action: action, at: at, success: success))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// Immutable snapshot of the current contents.
    public func snapshot() -> [Breadcrumb] {
        entries
    }

    private static let uuidRegex: NSRegularExpression = {
        // 8-4-4-4-12 hex with dashes, case-insensitive.
        let pattern = #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}
