import Foundation

// hasTags verified absent on 2026-05-14 — Plan 3's existing `Field.tag`
// + `Op.isUnset` already expresses "task has no tags" (see
// SmartFilterStore+Defaults.swift's `noTags` spec). Adding a parallel
// `Field.hasTags` would be dead code: this installer delegates to
// `SmartFilterStore.installDefaultsIfNeeded()`, which uses the
// existing `tag.isUnset` form. Plan 10 Task 4 skipped per its own
// "no-op when not needed" path.

/// Idempotently installs the five pre-installed default smart filters
/// described in design Section 7 ("Pre-installed defaults"):
///
/// - **Today**: tasks starting or due today, open, not in trash.
/// - **This Week**: tasks starting or due within 7 days, open, not in trash.
/// - **No Tags**: open tasks with zero tags.
/// - **Recently Closed**: tasks closed within the last 7 days.
/// - **Stale**: open tasks not modified in 30+ days.
///
/// The canonical specs live in `SmartFilterStore+Defaults.DefaultSmartFilters.all`
/// (Plan 7). This installer is a thin wrapper around
/// `SmartFilterStore.installDefaultsIfNeeded()` so the onboarding flow has a
/// stable Plan-10-named entry point without duplicating predicate definitions.
///
/// Matching is by exact filter name. A user who renames "Today" causes the
/// installer to re-create a fresh "Today" — that's expected. A user who
/// *deletes* a default and runs the installer again will see it restored.
///
/// The empty tag tree is the other half of design Section 7's
/// "Pre-installed defaults": this installer *deliberately* never creates
/// default tags.
public final class DefaultsInstaller: @unchecked Sendable {
    private let filters: SmartFilterStore

    public init(filters: SmartFilterStore) {
        self.filters = filters
    }

    /// Install any of the five default smart filters that don't already
    /// exist (matched by name). Idempotent across launches.
    public func installIfNeeded() async throws {
        try await filters.installDefaultsIfNeeded()
    }
}
