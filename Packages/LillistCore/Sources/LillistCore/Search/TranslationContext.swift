import Foundation

/// Everything a `FilterQueryTranslator` needs beyond the raw query string:
/// the tag vocabulary to resolve names against, the anchor time/calendar
/// relative dates resolve against (matching the rule engine's own
/// `now`/`calendar` convention — see `NSPredicateCompiler.compile`), and
/// which `Field`s are legal to reference.
public struct TranslationContext: Sendable {
    public var knownTags: [TagRef]
    public var now: Date
    public var calendar: Calendar
    public var availableFields: [Field]

    public init(
        knownTags: [TagRef] = [],
        now: Date = Date(),
        calendar: Calendar = .current,
        availableFields: [Field] = Field.allCases
    ) {
        self.knownTags = knownTags
        self.now = now
        self.calendar = calendar
        self.availableFields = availableFields
    }
}
