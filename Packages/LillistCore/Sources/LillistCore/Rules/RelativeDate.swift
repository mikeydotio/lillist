import Foundation

/// A date expressed relative to "now". Resolved to an absolute `Date` at
/// evaluation time so "next 7 days" always means *now's* +7 — never frozen
/// at smart-filter save time.
///
/// Codable + Sendable. The associated-value cases are encoded with a
/// discriminator key so JSON output is human-readable and stable.
public enum RelativeDate: Codable, Sendable, Equatable {
    case today
    case tomorrow
    case yesterday
    case daysFromNow(Int)
    case weeksFromNow(Int)
    case startOfWeek
    case endOfWeek
    case startOfMonth
    case endOfMonth

    // MARK: - Codable (manual, for stable discriminator JSON)

    private enum CodingKeys: String, CodingKey { case kind, count }

    private enum Kind: String, Codable {
        case today, tomorrow, yesterday
        case daysFromNow, weeksFromNow
        case startOfWeek, endOfWeek, startOfMonth, endOfMonth
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .today: self = .today
        case .tomorrow: self = .tomorrow
        case .yesterday: self = .yesterday
        case .daysFromNow: self = .daysFromNow(try c.decode(Int.self, forKey: .count))
        case .weeksFromNow: self = .weeksFromNow(try c.decode(Int.self, forKey: .count))
        case .startOfWeek: self = .startOfWeek
        case .endOfWeek: self = .endOfWeek
        case .startOfMonth: self = .startOfMonth
        case .endOfMonth: self = .endOfMonth
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .today: try c.encode(Kind.today, forKey: .kind)
        case .tomorrow: try c.encode(Kind.tomorrow, forKey: .kind)
        case .yesterday: try c.encode(Kind.yesterday, forKey: .kind)
        case .daysFromNow(let n):
            try c.encode(Kind.daysFromNow, forKey: .kind)
            try c.encode(n, forKey: .count)
        case .weeksFromNow(let n):
            try c.encode(Kind.weeksFromNow, forKey: .kind)
            try c.encode(n, forKey: .count)
        case .startOfWeek: try c.encode(Kind.startOfWeek, forKey: .kind)
        case .endOfWeek: try c.encode(Kind.endOfWeek, forKey: .kind)
        case .startOfMonth: try c.encode(Kind.startOfMonth, forKey: .kind)
        case .endOfMonth: try c.encode(Kind.endOfMonth, forKey: .kind)
        }
    }

    // MARK: - DSL parser

    /// Parse a DSL string into a `RelativeDate`.
    ///
    /// Accepted forms: keywords (`today`, `tomorrow`, `yesterday`,
    /// `startOfWeek`, `endOfWeek`, `startOfMonth`, `endOfMonth`); signed offset
    /// forms `+Nd` / `-Nd` / `+Nw` / `-Nw`; and bare unsigned forms `Nd` / `Nw`
    /// which behave as `+Nd` / `+Nw`. Case-insensitive.
    public static func parse(_ raw: String) throws -> RelativeDate {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "must not be empty")
            ])
        }
        let lower = s.lowercased()
        switch lower {
        case "today": return .today
        case "tomorrow": return .tomorrow
        case "yesterday": return .yesterday
        case "startofweek": return .startOfWeek
        case "endofweek": return .endOfWeek
        case "startofmonth": return .startOfMonth
        case "endofmonth": return .endOfMonth
        default: break
        }
        // Offset forms: optional sign, digits, unit suffix
        let pattern = #"^([+-]?)(\d+)([dw])$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let match = regex.firstMatch(
                in: lower,
                options: [],
                range: NSRange(lower.startIndex..., in: lower)
            ),
            match.numberOfRanges == 4
        else {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "unrecognized syntax: \(raw)")
            ])
        }
        let signRange = Range(match.range(at: 1), in: lower)!
        let numRange = Range(match.range(at: 2), in: lower)!
        let unitRange = Range(match.range(at: 3), in: lower)!
        let signStr = String(lower[signRange])
        let numStr = String(lower[numRange])
        let unit = String(lower[unitRange])
        guard let magnitude = Int(numStr) else {
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "invalid integer: \(raw)")
            ])
        }
        let signed = (signStr == "-") ? -magnitude : magnitude
        switch unit {
        case "d": return .daysFromNow(signed)
        case "w": return .weeksFromNow(signed)
        default:
            throw LillistError.validationFailed([
                .init(field: "relativeDate", message: "unknown unit: \(unit)")
            ])
        }
    }
}
