import Foundation

/// The recursive predicate type. v1 UIs build only single-level groups; the
/// data model is already nested for v2 nested-group authoring.
///
/// Codable is hand-written: automatic synthesis fails on mutually-recursive
/// types (`Predicate` ↔ `PredicateGroup.predicates: [Predicate]`).
public indirect enum Predicate: Codable, Sendable, Equatable {
    case leaf(Leaf)
    case group(PredicateGroup)

    private enum CodingKeys: String, CodingKey { case type, payload }

    private enum Kind: String, Codable {
        case leaf
        case group
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        switch kind {
        case .leaf:
            let leaf = try c.decode(Leaf.self, forKey: .payload)
            self = .leaf(leaf)
        case .group:
            let group = try c.decode(PredicateGroup.self, forKey: .payload)
            self = .group(group)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let l):
            try c.encode(Kind.leaf, forKey: .type)
            try c.encode(l, forKey: .payload)
        case .group(let g):
            try c.encode(Kind.group, forKey: .type)
            try c.encode(g, forKey: .payload)
        }
    }
}
