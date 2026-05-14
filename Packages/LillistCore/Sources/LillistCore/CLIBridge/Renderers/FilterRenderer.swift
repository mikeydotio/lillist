import Foundation

extension CLIBridge {
    public enum FilterRenderer {
        public struct PrettyFilterSummary: Sendable, Equatable {
            public var id: UUID
            public var name: String
            public var isPinned: Bool
            public var tintColor: String?
            public var sortField: SortField
            public var sortAscending: Bool
            public init(id: UUID, name: String, isPinned: Bool, tintColor: String?, sortField: SortField, sortAscending: Bool) {
                self.id = id
                self.name = name
                self.isPinned = isPinned
                self.tintColor = tintColor
                self.sortField = sortField
                self.sortAscending = sortAscending
            }
        }

        public static func prettyList(_ summaries: [PrettyFilterSummary], color: Bool) -> String {
            var out = ""
            for s in summaries {
                let pin = s.isPinned ? " (pinned)" : ""
                out += "\(s.name)\(pin) — sort: \(s.sortField.rawValue) \(s.sortAscending ? "asc" : "desc")\n"
            }
            return out
        }
    }
}
