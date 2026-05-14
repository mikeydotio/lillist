import Foundation

extension CLIBridge {
    public enum JournalRenderer {
        public struct JournalDTO: Codable, Sendable, Equatable {
            public var id: UUID
            public var taskID: UUID
            public var kind: String
            public var body: String
            public var createdAt: Date?
            public var editedAt: Date?
            public init(from r: JournalStore.JournalRecord) {
                self.id = r.id
                self.taskID = r.taskID
                self.kind = String(describing: r.kind)
                self.body = r.body
                self.createdAt = r.createdAt
                self.editedAt = r.editedAt
            }
        }

        public static func json(_ records: [JournalStore.JournalRecord]) throws -> Data {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            enc.dateEncodingStrategy = .iso8601
            return try enc.encode(records.map(JournalDTO.init(from:)))
        }

        public static func prettyList(_ records: [JournalStore.JournalRecord], color: Bool) -> String {
            let f = ISO8601DateFormatter()
            var out = ""
            for r in records {
                let when = r.createdAt.map { f.string(from: $0) } ?? "—"
                out += "[\(when)] \(r.kind): \(r.body)\n"
            }
            return out
        }
    }
}
