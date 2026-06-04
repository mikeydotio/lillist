import Foundation
@testable import LillistCore

/// One parity fixture. Seed each task with a stable id so expectations are
/// deterministic; expected ids are the ones that should pass the predicate.
struct ParityFixture: Sendable {
    let name: String
    let group: PredicateGroup
    let seeds: [SeedTask]
    let expected: Set<UUID>
}

/// A serializable description of a task to seed before running a fixture.
/// Mirrors `LillistTask`'s queryable fields plus a few relational fan-outs.
struct SeedTask: Sendable {
    var id: UUID = UUID()
    var title: String = "task"
    var notes: String = ""
    var status: Status = .todo
    var start: Date? = nil
    var deadline: Date? = nil
    var createdAt: Date = ParityFixtures.now
    var modifiedAt: Date = ParityFixtures.now
    var closedAt: Date? = nil
    var deletedAt: Date? = nil
    var isPinned: Bool = false
    var parentID: UUID? = nil
    var tagIDs: [UUID] = []
    var journalNoteBodies: [String] = []
    var attachmentKinds: [AttachmentKind] = []
    var isRecurring: Bool = false
    var hasNudges: Bool = false
}

enum ParityFixtures {
    /// Fixed "now" for relative-date fixtures: 2026-05-12 12:00 UTC.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 12
        c.hour = 12; c.minute = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    static func days(_ n: Int, from date: Date = now) -> Date {
        calendar.date(byAdding: .day, value: n, to: date)!
    }

    // Deterministic id pool for predictable expectations.
    static let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    static let id3 = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    static let id4 = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    static let id5 = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!

    static let tagWork = UUID(uuidString: "00000000-0000-0000-0001-000000000001")!
    static let tagHome = UUID(uuidString: "00000000-0000-0000-0001-000000000002")!
    static let tagUrgent = UUID(uuidString: "00000000-0000-0000-0001-000000000003")!

    static let parentA = UUID(uuidString: "00000000-0000-0000-0002-000000000001")!

    // Deep-chain ids for the ancestor-depth parity fixture (Task 1).
    static let chainRoot = UUID(uuidString: "00000000-0000-0000-0003-000000000000")!
    static func chainNode(_ depth: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0003-0000000000\(String(format: "%02d", depth))")!
    }

    static let all: [ParityFixture] = [
        // 1. title contains
        ParityFixture(
            name: "title contains 'design'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("design")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Design review"),
                SeedTask(id: id2, title: "Write spec")
            ],
            expected: [id1]
        ),
        // 2. title contains is case-insensitive
        ParityFixture(
            name: "title contains 'DESIGN' case-insensitive",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("DESIGN")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "design review"),
                SeedTask(id: id2, title: "spec")
            ],
            expected: [id1]
        ),
        // 3. title startsWith
        ParityFixture(
            name: "title startsWith 'Re'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .startsWith, value: .string("Re")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Refactor module"),
                SeedTask(id: id2, title: "Read mail"),
                SeedTask(id: id3, title: "Cleanup")
            ],
            expected: [id1, id2]
        ),
        // 4. notes contains
        ParityFixture(
            name: "notes contains 'sketch'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .notes, op: .contains, value: .string("sketch")))
            ]),
            seeds: [
                SeedTask(id: id1, notes: "rough sketch attached"),
                SeedTask(id: id2, notes: "no doodles")
            ],
            expected: [id1]
        ),
        // 5. status is {todo, started}
        ParityFixture(
            name: "status is {todo, started}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo),
                SeedTask(id: id2, status: .started),
                SeedTask(id: id3, status: .blocked),
                SeedTask(id: id4, status: .closed)
            ],
            expected: [id1, id2]
        ),
        // 6. status isNot {closed}
        ParityFixture(
            name: "status isNot {closed}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo),
                SeedTask(id: id2, status: .closed)
            ],
            expected: [id1]
        ),
        // 7. isPinned is true
        ParityFixture(
            name: "isPinned is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, isPinned: true),
                SeedTask(id: id2, isPinned: false)
            ],
            expected: [id1]
        ),
        // 8. deadline before today
        ParityFixture(
            name: "deadline before today",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .before, value: .relativeDate(.today)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(-1)),
                SeedTask(id: id2, deadline: days(1))
            ],
            expected: [id1]
        ),
        // 9. deadline withinNextDays(7)
        ParityFixture(
            name: "deadline withinNextDays(7)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(7)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(3)),
                SeedTask(id: id2, deadline: days(10)),
                SeedTask(id: id3, deadline: nil)
            ],
            expected: [id1]
        ),
        // 10. start withinLastDays(3)
        ParityFixture(
            name: "start withinLastDays(3)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .start, op: .withinLastDays, value: .dayCount(3)))
            ]),
            seeds: [
                SeedTask(id: id1, start: days(-1)),
                SeedTask(id: id2, start: days(-5))
            ],
            expected: [id1]
        ),
        // 11. deadline isSet
        ParityFixture(
            name: "deadline isSet",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, deadline: nil)
            ],
            expected: [id1]
        ),
        // 12. deadline isUnset
        ParityFixture(
            name: "deadline isUnset",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, deadline: nil)
            ],
            expected: [id2]
        ),
        // 13. createdAt equalsModifiedAt
        ParityFixture(
            name: "createdAt equalsModifiedAt (stale)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, createdAt: now, modifiedAt: now),
                SeedTask(id: id2, createdAt: now, modifiedAt: days(0, from: now).addingTimeInterval(60))
            ],
            expected: [id1]
        ),
        // 14. closedAt withinLastDays(7) (Recently Closed)
        ParityFixture(
            name: "closedAt withinLastDays(7)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .closedAt, op: .withinLastDays, value: .dayCount(7)))
            ]),
            seeds: [
                SeedTask(id: id1, status: .closed, closedAt: days(-2)),
                SeedTask(id: id2, status: .closed, closedAt: days(-20))
            ],
            expected: [id1]
        ),
        // 15. tag includesAny {work, home}
        ParityFixture(
            name: "tag includesAny {work, home}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagWork, tagHome])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagWork]),
                SeedTask(id: id2, tagIDs: [tagHome]),
                SeedTask(id: id3, tagIDs: [tagUrgent])
            ],
            expected: [id1, id2]
        ),
        // 16. tag includesAll {work, urgent}
        ParityFixture(
            name: "tag includesAll {work, urgent}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .includesAll, value: .uuidSet([tagWork, tagUrgent])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagWork, tagUrgent]),
                SeedTask(id: id2, tagIDs: [tagWork]),
                SeedTask(id: id3, tagIDs: [tagWork, tagHome, tagUrgent])
            ],
            expected: [id1, id3]
        ),
        // 17. tag excludesAll {work}
        ParityFixture(
            name: "tag excludesAll {work}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .excludesAll, value: .uuidSet([tagWork])))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: [tagHome]),
                SeedTask(id: id2, tagIDs: [tagWork]),
                SeedTask(id: id3, tagIDs: [])
            ],
            expected: [id1, id3]
        ),
        // 18. ancestor isDescendantOf {parentA}
        ParityFixture(
            name: "ancestor isDescendantOf {parentA}",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([parentA])))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, parentID: nil)
            ],
            expected: [id1]
        ),
        // 19. journalText contains
        ParityFixture(
            name: "journalText contains 'blocker'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .journalText, op: .contains, value: .string("blocker")))
            ]),
            seeds: [
                SeedTask(id: id1, journalNoteBodies: ["external blocker"]),
                SeedTask(id: id2, journalNoteBodies: ["all good"]),
                SeedTask(id: id3)
            ],
            expected: [id1]
        ),
        // 20. hasAttachments any
        ParityFixture(
            name: "hasAttachments is true (any kind)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasAttachments, op: .is,
                            value: .attachmentKind(.init(present: true))))
            ]),
            seeds: [
                SeedTask(id: id1, attachmentKinds: [.file]),
                SeedTask(id: id2, attachmentKinds: [])
            ],
            expected: [id1]
        ),
        // 21. hasAttachments ofKind=image
        ParityFixture(
            name: "hasAttachments image",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasAttachments, op: .is,
                            value: .attachmentKind(.init(present: true, kind: .image))))
            ]),
            seeds: [
                SeedTask(id: id1, attachmentKinds: [.image, .file]),
                SeedTask(id: id2, attachmentKinds: [.file])
            ],
            expected: [id1]
        ),
        // 22. hasChildren is true
        ParityFixture(
            name: "hasChildren is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasChildren, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, title: "Leaf")
            ],
            expected: [parentA]
        ),
        // 23. inTrash explicit true
        ParityFixture(
            name: "inTrash is true (explicit)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, deletedAt: nil),
                SeedTask(id: id2, deletedAt: now)
            ],
            expected: [id2]
        ),
        // 24. Implicit inTrash filter excludes deleted
        ParityFixture(
            name: "implicit inTrash filter excludes deleted",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("a")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "alpha", deletedAt: nil),
                SeedTask(id: id2, title: "apple", deletedAt: now)
            ],
            expected: [id1]
        ),
        // 25. Combinator .all
        ParityFixture(
            name: "all of: status=todo AND deadline isSet",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.todo]))),
                .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, status: .todo, deadline: days(1)),
                SeedTask(id: id2, status: .todo, deadline: nil),
                SeedTask(id: id3, status: .closed, deadline: days(1))
            ],
            expected: [id1]
        ),
        // 26. Combinator .any
        ParityFixture(
            name: "any of: pinned OR deadline within next 3 days",
            group: .init(combinator: .any, predicates: [
                .leaf(.init(field: .isPinned, op: .is, value: .bool(true))),
                .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(3)))
            ]),
            seeds: [
                SeedTask(id: id1, deadline: days(1)),
                SeedTask(id: id2, isPinned: true),
                SeedTask(id: id3, deadline: days(10), isPinned: false)
            ],
            expected: [id1, id2]
        ),
        // 27. Nested group: status=started AND (tag=work OR tag=urgent)
        ParityFixture(
            name: "nested: started AND (work OR urgent)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .status, op: .is, value: .statusSet([.started]))),
                .group(.init(combinator: .any, predicates: [
                    .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagWork]))),
                    .leaf(.init(field: .tag, op: .includesAny, value: .uuidSet([tagUrgent])))
                ]))
            ]),
            seeds: [
                SeedTask(id: id1, status: .started, tagIDs: [tagWork]),
                SeedTask(id: id2, status: .todo, tagIDs: [tagWork]),
                SeedTask(id: id3, status: .started, tagIDs: [tagHome])
            ],
            expected: [id1]
        ),
        // 28. Empty predicate group matches everything non-trashed
        ParityFixture(
            name: "empty group matches all non-trashed",
            group: .init(combinator: .all, predicates: []),
            seeds: [
                SeedTask(id: id1),
                SeedTask(id: id2, deletedAt: now)
            ],
            expected: [id1]
        ),
        // 29. title contains diacritic-insensitive
        ParityFixture(
            name: "title contains 'cafe' matches 'café'",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .title, op: .contains, value: .string("cafe")))
            ]),
            seeds: [
                SeedTask(id: id1, title: "Visit café"),
                SeedTask(id: id2, title: "Visit park")
            ],
            expected: [id1]
        ),
        // 30. createdAt after a fixed absolute date
        ParityFixture(
            name: "createdAt after fixed absolute date",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .createdAt, op: .after, value: .absoluteDate(ParityFixtures.days(-2))))
            ]),
            seeds: [
                SeedTask(id: id1, createdAt: now),
                SeedTask(id: id2, createdAt: days(-5))
            ],
            expected: [id1]
        ),
        // 31. tag isUnset — the "No Tags" default filter's leaf
        ParityFixture(
            name: "tag isUnset",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .isUnset, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: []),
                SeedTask(id: id2, tagIDs: [tagWork])
            ],
            expected: [id1]
        ),
        // 32. tag isSet
        ParityFixture(
            name: "tag isSet",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .tag, op: .isSet, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, tagIDs: []),
                SeedTask(id: id2, tagIDs: [tagWork])
            ],
            expected: [id2]
        ),
        // 33. ancestor isDescendantOf over a chain exactly at the depth ceiling.
        // A node at depth == maxAncestorDepth must match in BOTH evaluators;
        // a node one level deeper must match in NEITHER. Pre-fix, `from()`
        // walked 32 levels and the compiler walked 8, so depth-9 diverged.
        ParityFixture(
            name: "ancestor isDescendantOf chain at depth ceiling",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isDescendantOf, value: .uuidSet([chainRoot])))
            ]),
            seeds: {
                var out: [SeedTask] = [SeedTask(id: chainRoot, title: "root")]
                var parent = chainRoot
                // depth 1...9: nine nested children under chainRoot.
                for depth in 1...9 {
                    let nodeID = chainNode(depth)
                    out.append(SeedTask(id: nodeID, title: "depth-\(depth)", parentID: parent))
                    parent = nodeID
                }
                return out
            }(),
            // PredicateLimits.maxAncestorDepth == 8: depths 1...8 are reachable,
            // depth 9 is beyond the ceiling for both evaluators.
            expected: Set((1...8).map { chainNode($0) })
        ),
        // 34. recurrence is true — must surface only the recurring task in BOTH.
        ParityFixture(
            name: "recurrence is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .recurrence, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, title: "weekly review", isRecurring: true),
                SeedTask(id: id2, title: "one-off", isRecurring: false)
            ],
            expected: [id1]
        ),
        // 35. hasNudges is true — must surface only the nudged task in BOTH.
        ParityFixture(
            name: "hasNudges is true",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .hasNudges, op: .is, value: .bool(true)))
            ]),
            seeds: [
                SeedTask(id: id1, title: "reminder set", hasNudges: true),
                SeedTask(id: id2, title: "no reminder", hasNudges: false)
            ],
            expected: [id1]
        ),
        // 36. ancestor isAncestorOf {id1}: no surfaced caller, so BOTH
        // evaluators stub `false` — a parent of id1 must NOT be returned.
        ParityFixture(
            name: "ancestor isAncestorOf is unsupported (false in both)",
            group: .init(combinator: .all, predicates: [
                .leaf(.init(field: .ancestor, op: .isAncestorOf, value: .uuidSet([id1])))
            ]),
            seeds: [
                SeedTask(id: parentA, title: "Parent"),
                SeedTask(id: id1, parentID: parentA),
                SeedTask(id: id2, parentID: nil)
            ],
            expected: []
        )
    ]
}
