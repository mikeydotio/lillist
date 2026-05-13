import Foundation

/// The right-hand side of a `Leaf`. A discriminated union with a stable
/// `kind` field in JSON, so saved filters survive schema evolution.
public enum Value: Codable, Sendable, Equatable {
    case string(String)
    case uuidSet(Set<UUID>)
    case statusSet(Set<Status>)
    case bool(Bool)
    case absoluteDate(Date)
    case relativeDate(RelativeDate)
    case dayCount(Int)
    case attachmentKind(AttachmentKindMatch)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case kind, value }

    private enum Kind: String, Codable {
        case string, uuidSet, statusSet, bool
        case absoluteDate, relativeDate, dayCount, attachmentKind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .string:
            self = .string(try c.decode(String.self, forKey: .value))
        case .uuidSet:
            let arr = try c.decode([UUID].self, forKey: .value)
            self = .uuidSet(Set(arr))
        case .statusSet:
            let arr = try c.decode([Status].self, forKey: .value)
            self = .statusSet(Set(arr))
        case .bool:
            self = .bool(try c.decode(Bool.self, forKey: .value))
        case .absoluteDate:
            self = .absoluteDate(try c.decode(Date.self, forKey: .value))
        case .relativeDate:
            self = .relativeDate(try c.decode(RelativeDate.self, forKey: .value))
        case .dayCount:
            self = .dayCount(try c.decode(Int.self, forKey: .value))
        case .attachmentKind:
            self = .attachmentKind(try c.decode(AttachmentKindMatch.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let s):
            try c.encode(Kind.string, forKey: .kind)
            try c.encode(s, forKey: .value)
        case .uuidSet(let set):
            try c.encode(Kind.uuidSet, forKey: .kind)
            // Sort for deterministic JSON output.
            try c.encode(set.sorted(by: { $0.uuidString < $1.uuidString }), forKey: .value)
        case .statusSet(let set):
            try c.encode(Kind.statusSet, forKey: .kind)
            try c.encode(set.sorted(by: { $0.rawValue < $1.rawValue }), forKey: .value)
        case .bool(let b):
            try c.encode(Kind.bool, forKey: .kind)
            try c.encode(b, forKey: .value)
        case .absoluteDate(let d):
            try c.encode(Kind.absoluteDate, forKey: .kind)
            try c.encode(d, forKey: .value)
        case .relativeDate(let r):
            try c.encode(Kind.relativeDate, forKey: .kind)
            try c.encode(r, forKey: .value)
        case .dayCount(let n):
            try c.encode(Kind.dayCount, forKey: .kind)
            try c.encode(n, forKey: .value)
        case .attachmentKind(let m):
            try c.encode(Kind.attachmentKind, forKey: .kind)
            try c.encode(m, forKey: .value)
        }
    }
}
