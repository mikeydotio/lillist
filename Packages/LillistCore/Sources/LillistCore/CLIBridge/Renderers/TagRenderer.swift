import Foundation

extension CLIBridge {
    public enum TagRenderer {
        public struct TagDTO: Codable, Sendable, Equatable {
            public var id: UUID
            public var name: String
            public var tintColor: String?
            public var parentID: UUID?
            public var position: Double
            public init(from r: TagStore.TagRecord) {
                self.id = r.id
                self.name = r.name
                self.tintColor = r.tintColor
                self.parentID = r.parentID
                self.position = r.position
            }
        }

        public static func json(_ records: [TagStore.TagRecord]) throws -> Data {
            let dtos = records.map(TagDTO.init(from:))
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys, .prettyPrinted]
            return try enc.encode(dtos)
        }

        public static func ndjson(_ records: [TagStore.TagRecord]) throws -> String {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            var lines: [String] = []
            for r in records {
                let data = try enc.encode(TagDTO(from: r))
                lines.append(String(data: data, encoding: .utf8) ?? "")
            }
            return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        }

        public static func tsv(_ records: [TagStore.TagRecord]) -> String {
            var rows: [String] = ["id\tname\tparentID\ttintColor"]
            for r in records {
                rows.append([r.id.uuidString, r.name, r.parentID?.uuidString ?? "", r.tintColor ?? ""].joined(separator: "\t"))
            }
            return rows.joined(separator: "\n") + "\n"
        }

        public static func prettyTree(_ records: [TagStore.TagRecord], color: Bool) -> String {
            var byParent: [UUID?: [TagStore.TagRecord]] = [:]
            for r in records { byParent[r.parentID, default: []].append(r) }
            for k in byParent.keys { byParent[k]?.sort { $0.position < $1.position } }
            let ids = Set(records.map(\.id))
            let roots = records.filter { r in
                guard let pid = r.parentID else { return true }
                return ids.contains(pid) == false
            }.sorted { $0.position < $1.position }
            var out = ""
            for r in roots { render(r, depth: 0, byParent: byParent, color: color, into: &out) }
            return out
        }

        static func render(_ r: TagStore.TagRecord, depth: Int, byParent: [UUID?: [TagStore.TagRecord]], color: Bool, into out: inout String) {
            let indent = String(repeating: "  ", count: depth)
            let tag = "#\(r.name)"
            let coloured: String
            if color, let hex = r.tintColor, let ansi = ansiFor(hex: hex) {
                coloured = "\(ansi)\(tag)\u{001B}[0m"
            } else {
                coloured = tag
            }
            out += "\(indent)\(coloured)\n"
            for c in byParent[r.id] ?? [] { render(c, depth: depth + 1, byParent: byParent, color: color, into: &out) }
        }

        static func ansiFor(hex: String) -> String? {
            // Crude mapping: any non-empty hex → cyan. Real impl in Plan 7 UI;
            // here we just signal "has color."
            return hex.isEmpty ? nil : "\u{001B}[36m"
        }
    }
}
