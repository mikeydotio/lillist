import Foundation

/// The right-hand side of an `IntermediateClause`. A flat, guided-generation
/// friendly counterpart to `Value` — no `Set`, no raw `Date`, no tag ids.
/// Guided generation (Apple's `@Generable`/`@Guide`) works over plain enums
/// and arrays, and a translator only ever knows tag *names* (resolved to ids
/// by `IntermediateFilterMapper` via `TranslationContext.knownTags`), so this
/// type exists specifically to stay representable by that constraint —
/// `IntermediateFilterMapper` is what converts it into a real `Value`.
public enum IntermediateValue: Sendable, Equatable {
    /// `title` / `notes` / `journalText` — `contains` / `equals` / `startsWith`.
    case text(String)
    /// `tag` — `includesAny` / `includesAll` / `excludesAll`. Names, not ids.
    case tagNames([String])
    /// `status` — `is` / `isNot`.
    case statuses([Status])
    /// Any boolean field (`isPinned`, `hasChildren`, `hasNudges`,
    /// `recurrence`, `inTrash`) — `is`.
    case boolean(Bool)
    /// A date field's absolute target, as an ISO-8601 string (day or
    /// date-time granularity) — `before` / `after` / `on`. Parsed by the
    /// mapper; an unparsable string drops the clause rather than throwing.
    case absoluteDateISO8601(String)
    /// A date field's relative target — `before` / `after` / `on`.
    case relativeDate(RelativeDate)
    /// A date field's day-window count — `withinLastDays` / `withinNextDays`.
    case dayCount(Int)
    /// `hasAttachments` — `is`.
    case attachmentKind(AttachmentKindMatch)
    /// No payload needed: `isSet` / `isUnset` / `equalsModifiedAt` / the
    /// `isAncestorOf` stub — the (field, op) pair alone determines the
    /// resulting `Leaf`.
    case none
}
