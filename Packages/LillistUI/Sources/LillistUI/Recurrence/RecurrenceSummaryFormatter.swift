import Foundation
import LillistCore

/// Renders a `RecurrenceSummary` into a localized, correctly-pluralized
/// string using LillistUI's own string catalog (`bundle: .module`).
///
/// All wording lives in `Resources/Localizable.xcstrings`; this type only
/// selects the right key.
///
/// Pluralization is handled by branching on the count (`interval == 1` /
/// `days == 1` route to a dedicated singular key; the `>= 2` cases route
/// to the `%lld` key whose source form is already plural). This is the
/// same pattern the calendar `interval == 1` case uses, and it keeps
/// English correct **without** relying on a compiled string catalog —
/// SwiftPM copies `.xcstrings` into the resource bundle verbatim (it does
/// NOT run `xcstringstool` the way Xcode does), so a `.xcstrings`
/// plural-variation would be inert under `swift test`. The interpolated
/// `%lld` key carries the count for translators (and resolves plural
/// variations correctly once the catalog is compiled by Xcode for the
/// shipping app), while the source-language string the host test sees is
/// already grammatically correct.
public enum RecurrenceSummaryFormatter {
    /// Renders `summary` for `locale` (defaults to `.current`).
    public static func string(
        for summary: RecurrenceSummary,
        locale: Locale = .current
    ) -> String {
        switch summary {
        case .never:
            return String(localized: "Doesn't repeat", bundle: .module, locale: locale)

        case let .calendar(frequency, interval):
            // interval == 1 is its own non-pluralized key so "Every day"
            // never reads "Every 1 day"; interval >= 2 routes through the
            // pluralized "%lld" key whose catalog variation handles count.
            switch frequency {
            case .daily:
                return interval == 1
                    ? String(localized: "Every day", bundle: .module, locale: locale)
                    : String(localized: "Every \(interval) days", bundle: .module, locale: locale)
            case .weekly:
                return interval == 1
                    ? String(localized: "Every week", bundle: .module, locale: locale)
                    : String(localized: "Every \(interval) weeks", bundle: .module, locale: locale)
            case .monthly:
                return interval == 1
                    ? String(localized: "Every month", bundle: .module, locale: locale)
                    : String(localized: "Every \(interval) months", bundle: .module, locale: locale)
            case .yearly:
                return interval == 1
                    ? String(localized: "Every year", bundle: .module, locale: locale)
                    : String(localized: "Every \(interval) years", bundle: .module, locale: locale)
            }

        case let .afterCompletion(days):
            return days == 1
                ? String(localized: "Repeats 1 day after completion", bundle: .module, locale: locale)
                : String(localized: "Repeats \(days) days after completion", bundle: .module, locale: locale)
        }
    }
}
