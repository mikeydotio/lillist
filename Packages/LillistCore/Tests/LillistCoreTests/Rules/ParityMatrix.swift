import Foundation
@testable import LillistCore

/// A `Field × Op × Value` parity matrix. Each cell is a `ParityFixture`
/// (a `PredicateGroup` plus seeds plus the expected id set), so the proven
/// in-memory Core Data harness in `ParitySuiteTests` runs every cell against
/// BOTH evaluators with no harness changes. The matrix deliberately includes
/// negative / nil / empty / diacritic / case cells and the four formerly
/// divergent ops (equals-with-diacritic, recurrence, hasNudges, isAncestorOf).
enum ParityMatrix {
    private typealias F = ParityFixtures

    /// Seed ids reserved for the matrix so they never collide with the
    /// hand-written fixture ids.
    static let m1 = UUID(uuidString: "00000000-0000-0000-0004-000000000001")!
    static let m2 = UUID(uuidString: "00000000-0000-0000-0004-000000000002")!
    static let m3 = UUID(uuidString: "00000000-0000-0000-0004-000000000003")!

    static let all: [ParityFixture] = [
        // --- String × {contains, equals, startsWith} incl. case/diacritic/empty ---
        ParityFixture(
            name: "matrix: title contains 'spec' (positive + negative)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("spec")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "write spec"),
                SeedTask(id: m2, title: "unrelated")
            ],
            expected: [m1]
        ),
        ParityFixture(
            // Empty needle matches NOTHING in this engine: both NSPredicate
            // `CONTAINS[cd] ""` and `String.localizedStandardContains("")`
            // return false. Pin the agreed (empty) result so the parity matrix
            // documents the real behaviour rather than an assumed one.
            name: "matrix: title contains '' (empty needle matches nothing)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "anything"),
                SeedTask(id: m2, title: "")
            ],
            expected: []
        ),
        ParityFixture(
            name: "matrix: title equals 'Inbox' (case fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .equals, value: .string("Inbox")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "inbox"),
                SeedTask(id: m2, title: "Inbox zero")
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: title equals 'cafe' (diacritic fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .equals, value: .string("cafe")))
            ]),
            seeds: [
                SeedTask(id: m1, title: "café"),
                SeedTask(id: m2, title: "cafeteria")
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: notes startsWith 'TODO' (anchored, case fold)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .notes, op: .startsWith, value: .string("TODO")))
            ]),
            seeds: [
                SeedTask(id: m1, notes: "todo: follow up"),
                SeedTask(id: m2, notes: "a todo later")
            ],
            expected: [m1]
        ),

        // --- Status × {is, isNot} ---
        ParityFixture(
            name: "matrix: status isNot {closed}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]),
            seeds: [
                SeedTask(id: m1, status: .started),
                SeedTask(id: m2, status: .closed)
            ],
            expected: [m1]
        ),

        // --- Bool × is (isPinned, including the negative match) ---
        ParityFixture(
            name: "matrix: isPinned is false",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(false)))
            ]),
            seeds: [
                SeedTask(id: m1, isPinned: false),
                SeedTask(id: m2, isPinned: true)
            ],
            expected: [m1]
        ),

        // --- Date × {before, after, on, withinNextDays, withinLastDays, isSet, isUnset} ---
        // These cells are seeded relative to ParityFixtures.now; the suite
        // re-derives the expected set per calendar by re-seeding (see Step 3).
        ParityFixture(
            name: "matrix: deadline isUnset (nil case)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, deadline: nil),
                SeedTask(id: m2, deadline: F.days(1))
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: deadline on today (day window)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .on, value: .relativeDate(.today)))
            ]),
            seeds: [
                // Offset 0 = noon-of-today in the run calendar (mid-window, never
                // an edge); +1 = clearly the next day. Relative so membership is
                // identical under UTC and the DST calendar.
                SeedTask(id: m1, deadlineDayOffset: 0),
                SeedTask(id: m2, deadlineDayOffset: 1)
            ],
            expected: [m1]
        ),

        // --- Set ops × tag {includesAny, includesAll, excludesAll, isSet, isUnset} ---
        ParityFixture(
            name: "matrix: tag isUnset (empty set)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, tagIDs: []),
                SeedTask(id: m2, tagIDs: [F.tagWork])
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: tag excludesAll {work} (incl. no-tag task)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([F.tagWork])))
            ]),
            seeds: [
                SeedTask(id: m1, tagIDs: [F.tagHome]),
                SeedTask(id: m2, tagIDs: [F.tagWork]),
                SeedTask(id: m3, tagIDs: [])
            ],
            expected: [m1, m3]
        ),

        // --- The four formerly-divergent ops ---
        ParityFixture(
            name: "matrix: recurrence is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .recurrence, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, isRecurring: true),
                SeedTask(id: m2, isRecurring: false)
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: hasNudges is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasNudges, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: m1, hasNudges: true),
                SeedTask(id: m2, hasNudges: false)
            ],
            expected: [m1]
        ),
        ParityFixture(
            name: "matrix: ancestor isDescendantOf {m1}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([m1])))
            ]),
            seeds: [
                SeedTask(id: m1, title: "root"),
                SeedTask(id: m2, parentID: m1),
                SeedTask(id: m3, parentID: nil)
            ],
            expected: [m2]
        ),
        ParityFixture(
            name: "matrix: ancestor isAncestorOf {m2} (false in both)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isAncestorOf, value: .uuidSet([m2])))
            ]),
            seeds: [
                SeedTask(id: m1, title: "root"),
                SeedTask(id: m2, parentID: m1)
            ],
            expected: []
        )
    ]
}
