import LillistCore

/// Structured, non-localized description of a recurrence configuration.
///
/// Produced by `RecurrenceEditorViewModel.summary` (the data layer) and
/// rendered to a localized, correctly-pluralized string by
/// `RecurrenceSummaryFormatter` (the View layer). Keeping the shape here
/// and the wording there preserves separation of concerns: the value
/// type never embeds English or pluralization rules.
public enum RecurrenceSummary: Equatable, Sendable {
    /// The task does not repeat.
    case never
    /// A calendar rule firing every `interval` units of `frequency`.
    case calendar(_ frequency: RecurrenceRule.Frequency, interval: Int)
    /// An after-completion rule firing `days` after each completion.
    case afterCompletion(days: Int)
}
