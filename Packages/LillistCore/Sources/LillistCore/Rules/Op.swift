import Foundation

/// Every operator that may appear in a `Leaf`, per design Section 5.
///
/// `is`/`isNot` is a Swift keyword in some contexts; backtick-escape at use
/// sites: `Op.is`, `Op.isNot`.
public enum Op: String, CaseIterable, Codable, Sendable {
    case contains
    case equals
    case startsWith
    case includesAny
    case includesAll
    case excludesAll
    case `is`
    case isNot
    case before
    case after
    case on
    case withinLastDays
    case withinNextDays
    case isSet
    case isUnset
    case equalsModifiedAt
    case isDescendantOf
    case isAncestorOf
}
