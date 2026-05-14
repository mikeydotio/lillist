import Foundation

extension CLIBridge {
    /// Renders task records to the four output formats supported by the CLI.
    public enum TaskRenderer {
        /// JSON DTO mirroring `TaskRecord` with stable field names.
        public struct TaskDTO: Codable, Sendable, Equatable {
            public var id: UUID
            public var title: String
            public var notes: String
            public var status: String
            public var start: Date?
            public var startHasTime: Bool
            public var deadline: Date?
            public var deadlineHasTime: Bool
            public var position: Double
            public var isPinned: Bool
            public var parentID: UUID?
            public var createdAt: Date?
            public var modifiedAt: Date?
            public var closedAt: Date?
            public var deletedAt: Date?

            public init(from record: TaskStore.TaskRecord) {
                self.id = record.id
                self.title = record.title
                self.notes = record.notes
                self.status = String(describing: record.status)
                self.start = record.start
                self.startHasTime = record.startHasTime
                self.deadline = record.deadline
                self.deadlineHasTime = record.deadlineHasTime
                self.position = record.position
                self.isPinned = record.isPinned
                self.parentID = record.parentID
                self.createdAt = record.createdAt
                self.modifiedAt = record.modifiedAt
                self.closedAt = record.closedAt
                self.deletedAt = record.deletedAt
            }
        }

        // MARK: - JSON

        public static func json(_ records: [TaskStore.TaskRecord]) throws -> Data {
            let dtos = records.map(TaskDTO.init(from:))
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            enc.dateEncodingStrategy = .iso8601
            return try enc.encode(dtos)
        }

        public static func jsonString(_ records: [TaskStore.TaskRecord]) throws -> String {
            String(data: try json(records), encoding: .utf8) ?? ""
        }

        // MARK: - NDJSON

        public static func ndjson(_ records: [TaskStore.TaskRecord]) throws -> String {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            enc.dateEncodingStrategy = .iso8601
            var lines: [String] = []
            for r in records {
                let data = try enc.encode(TaskDTO(from: r))
                lines.append(String(data: data, encoding: .utf8) ?? "")
            }
            return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        }

        // MARK: - TSV

        public static func tsv(_ records: [TaskStore.TaskRecord]) throws -> String {
            let header = ["id", "title", "status", "start", "deadline", "isPinned", "parentID"].joined(separator: "\t")
            var rows: [String] = [header]
            let iso = ISO8601DateFormatter()
            for r in records {
                let cols = [
                    r.id.uuidString,
                    r.title.replacingOccurrences(of: "\t", with: " "),
                    String(describing: r.status),
                    r.start.map { iso.string(from: $0) } ?? "",
                    r.deadline.map { iso.string(from: $0) } ?? "",
                    r.isPinned ? "true" : "false",
                    r.parentID?.uuidString ?? ""
                ]
                rows.append(cols.joined(separator: "\t"))
            }
            return rows.joined(separator: "\n") + "\n"
        }

        // MARK: - Pretty tree

        public static func prettyTree(_ records: [TaskStore.TaskRecord], color: Bool) -> String {
            var byParent: [UUID?: [TaskStore.TaskRecord]] = [:]
            for r in records { byParent[r.parentID, default: []].append(r) }
            for k in byParent.keys {
                byParent[k]?.sort { $0.position < $1.position }
            }
            let recordIDs = Set(records.map(\.id))
            // Roots are records whose parent is nil OR whose parent is not in the visible set.
            let roots = records.filter { r in
                guard let pid = r.parentID else { return true }
                return recordIDs.contains(pid) == false
            }.sorted { $0.position < $1.position }

            var out = ""
            for r in roots {
                renderNode(r, depth: 0, byParent: byParent, color: color, into: &out)
            }
            return out
        }

        static func renderNode(
            _ r: TaskStore.TaskRecord,
            depth: Int,
            byParent: [UUID?: [TaskStore.TaskRecord]],
            color: Bool,
            into out: inout String
        ) {
            let indent = String(repeating: "  ", count: depth)
            let glyph = statusGlyph(r.status, color: color)
            out += "\(indent)\(glyph) \(r.title)\n"
            for child in byParent[r.id] ?? [] {
                renderNode(child, depth: depth + 1, byParent: byParent, color: color, into: &out)
            }
        }

        static func statusGlyph(_ status: Status, color: Bool) -> String {
            let base: String
            switch status {
            case .todo: base = "◯"
            case .started: base = "◐"
            case .blocked: base = "◌"
            case .closed: base = "✓"
            }
            guard color else { return base }
            let ansi: String
            switch status {
            case .todo: ansi = "\u{001B}[37m"        // white
            case .started: ansi = "\u{001B}[33m"     // yellow
            case .blocked: ansi = "\u{001B}[31m"     // red
            case .closed: ansi = "\u{001B}[32m"      // green
            }
            return "\(ansi)\(base)\u{001B}[0m"
        }
    }
}
