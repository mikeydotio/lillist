import Foundation

/// Parses Quick Capture text per design Section 7:
/// `#tag` adds a tag, `^phrase` sets a deadline (resolved later by LillistCore's date DSL).
public enum QuickCaptureParser {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var tags: [String]
        public var dateToken: String?

        public init(title: String, tags: [String], dateToken: String?) {
            self.title = title
            self.tags = tags
            self.dateToken = dateToken
        }
    }

    public static func parse(_ input: String) -> Result {
        var tags: [String] = []
        var dateToken: String?
        var titleParts: [String] = []

        for token in input.split(separator: " ", omittingEmptySubsequences: true) {
            if token.hasPrefix("#"), token.count > 1 {
                tags.append(String(token.dropFirst()))
            } else if token.hasPrefix("^"), token.count > 1 {
                dateToken = String(token.dropFirst())
            } else {
                titleParts.append(String(token))
            }
        }

        return Result(
            title: titleParts.joined(separator: " "),
            tags: tags,
            dateToken: dateToken
        )
    }
}
