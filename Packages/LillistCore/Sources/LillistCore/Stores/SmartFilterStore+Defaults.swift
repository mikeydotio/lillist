import Foundation

extension SmartFilterStore {
    /// Idempotently install the five default smart filters from design
    /// Section 7: Today, This Week, No Tags, Recently Closed, Stale.
    ///
    /// On second invocation, filters that already exist by name are left
    /// untouched (including user edits — the installer does NOT overwrite).
    /// Missing filters are recreated, so deleting "Today" and relaunching
    /// brings it back.
    ///
    /// Runs ``deduplicateExactDuplicates()`` first: the by-name idempotency check
    /// only sees the *local* store, which races `NSPersistentCloudKitContainer`'s
    /// async mirror — a launch on a not-yet-synced store re-creates the defaults,
    /// then the cloud copies sync in, leaving duplicates. Deduping before the
    /// create pass collapses those and keeps seeding self-healing across launches.
    public func installDefaultsIfNeeded() async throws {
        try await deduplicateExactDuplicates()

        let existing = try await list()
        let existingNames = Set(existing.map(\.name))

        for spec in DefaultSmartFilters.all where !existingNames.contains(spec.name) {
            _ = try await create(
                name: spec.name,
                group: spec.group,
                tintColor: spec.tintColor,
                sortField: spec.sortField,
                sortAscending: spec.sortAscending
            )
        }
    }

    /// Collapse **exact structural duplicates** — filters identical in
    /// `(name, group, sortField, sortAscending, tintColor)`. Only byte-identical
    /// copies are merged, so a user-customized filter that merely shares a name
    /// with a default is never touched. Idempotent.
    ///
    /// This is the cleanup half of the CloudKit-seed-race fix (Apple's
    /// "deduplicate after import" pattern): the winner is deterministic across
    /// devices — a pinned row beats an unpinned one, then the earliest
    /// `createdAt`, then the lowest `id` — so two devices deduping independently
    /// delete the same losers. Deletes propagate through CloudKit, clearing the
    /// duplicates everywhere.
    public func deduplicateExactDuplicates() async throws {
        let all = try await list()

        var kept: [SmartFilterRecord] = []
        var losers: [UUID] = []
        for record in all {
            if let idx = kept.firstIndex(where: { Self.isSameFilter($0, record) }) {
                if Self.winner(kept[idx], record).id == record.id {
                    losers.append(kept[idx].id)   // the incumbent loses
                    kept[idx] = record
                } else {
                    losers.append(record.id)
                }
            } else {
                kept.append(record)
            }
        }

        for id in losers {
            try? await delete(id: id)
        }
    }

    /// Structural equality: same name, predicate, sort, and tint. `PredicateGroup`
    /// is `Equatable`, so this is an exact byte-for-byte match.
    private static func isSameFilter(_ a: SmartFilterRecord, _ b: SmartFilterRecord) -> Bool {
        a.name == b.name
            && a.group == b.group
            && a.sortField == b.sortField
            && a.sortAscending == b.sortAscending
            && a.tintColor == b.tintColor
    }

    /// Deterministic survivor between two identical filters: prefer a pinned row,
    /// then the earliest `createdAt`, then the lexicographically lowest `id`.
    private static func winner(_ a: SmartFilterRecord, _ b: SmartFilterRecord) -> SmartFilterRecord {
        if a.isPinned != b.isPinned { return a.isPinned ? a : b }
        switch (a.createdAt, b.createdAt) {
        case let (ca?, cb?) where ca != cb: return ca < cb ? a : b
        case (_?, nil): return a
        case (nil, _?): return b
        default: break
        }
        return a.id.uuidString <= b.id.uuidString ? a : b
    }
}

enum DefaultSmartFilters {
    struct Spec {
        let name: String
        let group: PredicateGroup
        let tintColor: String?
        let sortField: SortField
        let sortAscending: Bool
    }

    static let all: [Spec] = [today, thisWeek, noTags, recentlyClosed, stale]

    // Today: status not closed AND (deadline on today OR start on today)
    private static var today: Spec {
        Spec(
            name: "Today",
            group: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed]))),
                    .group(PredicateGroup(
                        combinator: .any,
                        predicates: [
                            .leaf(Leaf(field: .deadline, op: .on, value: .relativeDate(.today))),
                            .leaf(Leaf(field: .start, op: .on, value: .relativeDate(.today)))
                        ]
                    ))
                ]
            ),
            tintColor: nil,
            sortField: .deadline,
            sortAscending: true
        )
    }

    // This Week: status not closed AND (deadline within next 7 days OR start within last 7 days)
    private static var thisWeek: Spec {
        Spec(
            name: "This Week",
            group: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed]))),
                    .group(PredicateGroup(
                        combinator: .any,
                        predicates: [
                            .leaf(Leaf(field: .deadline, op: .withinNextDays, value: .dayCount(7))),
                            .leaf(Leaf(field: .start, op: .withinLastDays, value: .dayCount(7)))
                        ]
                    ))
                ]
            ),
            tintColor: nil,
            sortField: .deadline,
            sortAscending: true
        )
    }

    // No Tags: status not closed AND tag isUnset
    private static var noTags: Spec {
        Spec(
            name: "No Tags",
            group: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed]))),
                    .leaf(Leaf(field: .tag, op: .isUnset, value: .bool(true)))
                ]
            ),
            tintColor: nil,
            sortField: .modifiedAt,
            sortAscending: false
        )
    }

    // Recently Closed: closedAt within last 7 days
    private static var recentlyClosed: Spec {
        Spec(
            name: "Recently Closed",
            group: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(Leaf(field: .closedAt, op: .withinLastDays, value: .dayCount(7)))
                ]
            ),
            tintColor: nil,
            sortField: .closedAt,
            sortAscending: false
        )
    }

    // Stale: todo status AND not modified in 30+ days
    private static var stale: Spec {
        Spec(
            name: "Stale",
            group: PredicateGroup(
                combinator: .all,
                predicates: [
                    .leaf(Leaf(field: .status, op: .is, value: .statusSet([.todo]))),
                    .leaf(Leaf(field: .modifiedAt, op: .before, value: .relativeDate(.daysFromNow(-30))))
                ]
            ),
            tintColor: nil,
            sortField: .modifiedAt,
            sortAscending: true
        )
    }
}
