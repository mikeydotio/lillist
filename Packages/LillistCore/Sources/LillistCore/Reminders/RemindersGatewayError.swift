import Foundation

/// Failures a ``RemindersGateway`` can throw while reading a list.
///
/// Replaces the previous "silent empty array" behavior: a resolvable-but-empty
/// list is a legitimate `[]` return, but a list that *can't be read* must not
/// be indistinguishable from one — that conflation is the origin of issue #50
/// ("Drain now" always reporting "Imported 0 tasks", even when the real cause
/// was a stale list identifier or a fetch failure).
public enum RemindersGatewayError: Error, Equatable, Sendable {
    /// `EKCalendar.calendarIdentifier` no longer resolves to a list on this
    /// `EKEventStore` — most commonly a persisted identifier gone stale after
    /// an account re-sync (CalDAV/Google lists aren't guaranteed stable ids).
    case listUnavailable(id: String)

    /// The list resolved, but the underlying EventKit fetch itself failed.
    case fetchFailed(id: String)
}
