import Foundation

extension SmartFilterStore {
    /// Idempotently install the five default smart filters from design
    /// Section 7: Today, This Week, No Tags, Recently Closed, Stale.
    ///
    /// On second invocation, filters that already exist by name are left
    /// untouched (including user edits — the installer does NOT overwrite).
    /// Missing filters are recreated, so deleting "Today" and relaunching
    /// brings it back.
    public func installDefaultsIfNeeded() async throws {
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
