import Testing
import Foundation
@testable import LillistCore

@Suite("IntermediateFilterMapper")
struct IntermediateFilterMapperTests {
    static let ctx = TranslationContext(
        knownTags: [
            TagRef(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Work"),
            TagRef(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Home")
        ],
        now: Date(timeIntervalSince1970: 1_700_000_000),
        calendar: .current
    )

    private func map(_ clause: IntermediateClause, combinator: PredicateGroup.Combinator = .all) -> MappingResult {
        IntermediateFilterMapper.map(
            IntermediateFilter(combinator: combinator, clauses: [clause]),
            context: Self.ctx
        )
    }

    // MARK: - String-like fields (title / notes / journalText)

    @Test("title/notes support contains, equals, startsWith")
    func stringLikeLegalOps() {
        for field in [Field.title, .notes] {
            for op in [Op.contains, .equals, .startsWith] {
                let result = map(IntermediateClause(field: field, op: op, value: .text("spec")))
                #expect(result.dropped.isEmpty, "\(field) \(op) should be legal")
                #expect(result.group.predicates == [.leaf(Leaf(field: field, op: op, value: .string("spec")))])
            }
        }
    }

    @Test("journalText supports contains only")
    func journalTextOnlyContains() {
        let ok = map(IntermediateClause(field: .journalText, op: .contains, value: .text("note")))
        #expect(ok.dropped.isEmpty)
        #expect(ok.group.predicates == [.leaf(Leaf(field: .journalText, op: .contains, value: .string("note")))])

        for op in [Op.equals, .startsWith] {
            let bad = map(IntermediateClause(field: .journalText, op: op, value: .text("note")))
            #expect(bad.dropped == [DroppedClause(field: .journalText, op: op, reason: .offMatrix)])
            #expect(bad.group.predicates.isEmpty)
        }
    }

    @Test("string-like field with a non-text value is dropped, not miscompiled")
    func stringLikeWrongValueKind() {
        let result = map(IntermediateClause(field: .title, op: .contains, value: .boolean(true)))
        #expect(result.dropped == [DroppedClause(field: .title, op: .contains, reason: .wrongValueKind)])
    }

    // MARK: - status

    @Test("status supports is/isNot with a non-empty status set")
    func statusLegal() {
        let isResult = map(IntermediateClause(field: .status, op: .is, value: .statuses([.closed])))
        #expect(isResult.group.predicates == [.leaf(Leaf(field: .status, op: .is, value: .statusSet([.closed])))])

        let isNotResult = map(IntermediateClause(field: .status, op: .isNot, value: .statuses([.closed])))
        #expect(isNotResult.group.predicates == [.leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))])
    }

    @Test("'is incomplete' maps to status isNot closed — the issue's own example")
    func incompleteExample() {
        let result = map(IntermediateClause(field: .status, op: .isNot, value: .statuses([.closed])))
        #expect(result.dropped.isEmpty)
        #expect(result.group.predicates == [.leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))])
    }

    @Test("status with an illegal op is off-matrix")
    func statusIllegalOp() {
        let result = map(IntermediateClause(field: .status, op: .contains, value: .statuses([.closed])))
        #expect(result.dropped == [DroppedClause(field: .status, op: .contains, reason: .offMatrix)])
    }

    @Test("status with an empty status set is wrongValueKind")
    func statusEmptySet() {
        let result = map(IntermediateClause(field: .status, op: .is, value: .statuses([])))
        #expect(result.dropped == [DroppedClause(field: .status, op: .is, reason: .wrongValueKind)])
    }

    // MARK: - boolean fields

    @Test("every boolean field supports only `is`")
    func booleanFieldsLegal() {
        for field in [Field.isPinned, .hasChildren, .hasNudges, .recurrence, .inTrash] {
            let ok = map(IntermediateClause(field: field, op: .is, value: .boolean(true)))
            #expect(ok.group.predicates == [.leaf(Leaf(field: field, op: .is, value: .bool(true)))])

            let bad = map(IntermediateClause(field: field, op: .contains, value: .boolean(true)))
            #expect(bad.dropped == [DroppedClause(field: field, op: .contains, reason: .offMatrix)])
        }
    }

    // MARK: - tag

    @Test("tag includesAny/includesAll/excludesAll resolve known names to ids")
    func tagMembershipResolves() {
        let workID = Self.ctx.knownTags[0].id
        for op in [Op.includesAny, .includesAll, .excludesAll] {
            let result = map(IntermediateClause(field: .tag, op: op, value: .tagNames(["Work"])))
            #expect(result.dropped.isEmpty)
            #expect(result.unresolvedTagNames.isEmpty)
            #expect(result.group.predicates == [.leaf(Leaf(field: .tag, op: op, value: .uuidSet([workID])))])
        }
    }

    @Test("tag name resolution is case-insensitive")
    func tagNameCaseInsensitive() {
        let workID = Self.ctx.knownTags[0].id
        let result = map(IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["wORK"])))
        #expect(result.group.predicates == [.leaf(Leaf(field: .tag, op: .includesAny, value: .uuidSet([workID])))])
    }

    @Test("unknown tag names are reported but the leaf still emits (matches nothing), mirroring FilterFlags")
    func unknownTagNameReported() {
        let result = map(IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Nonexistent"])))
        #expect(result.dropped.isEmpty, "the clause itself is representable, just with an empty uuidSet")
        #expect(result.unresolvedTagNames == ["Nonexistent"])
        #expect(result.group.predicates == [.leaf(Leaf(field: .tag, op: .includesAny, value: .uuidSet([])))])
    }

    @Test("tag includesAny with an empty name list is wrongValueKind")
    func tagEmptyNames() {
        let result = map(IntermediateClause(field: .tag, op: .includesAny, value: .tagNames([])))
        #expect(result.dropped == [DroppedClause(field: .tag, op: .includesAny, reason: .wrongValueKind)])
    }

    @Test("tag isSet/isUnset ignore the value payload (cardinality, not membership)")
    func tagCardinality() {
        for op in [Op.isSet, .isUnset] {
            let result = map(IntermediateClause(field: .tag, op: op, value: .none))
            #expect(result.dropped.isEmpty)
            #expect(result.group.predicates == [.leaf(Leaf(field: .tag, op: op, value: .bool(true)))])
        }
    }

    @Test("'has no tags' — the No Tags default filter's own idiom")
    func hasNoTagsIdiom() {
        let result = map(IntermediateClause(field: .tag, op: .isUnset, value: .none))
        #expect(result.group.predicates == [.leaf(Leaf(field: .tag, op: .isUnset, value: .bool(true)))])
    }

    // MARK: - date fields

    @Test("date fields support before/after/on with a relative date")
    func dateRelative() {
        for field in [Field.start, .deadline, .createdAt, .modifiedAt, .closedAt] {
            for op in [Op.before, .after, .on] {
                let result = map(IntermediateClause(field: field, op: op, value: .relativeDate(.today)))
                #expect(result.dropped.isEmpty, "\(field) \(op) relativeDate should be legal")
                #expect(result.group.predicates == [.leaf(Leaf(field: field, op: op, value: .relativeDate(.today)))])
            }
        }
    }

    @Test("'added before today' — the issue's own example")
    func addedBeforeTodayExample() {
        let result = map(IntermediateClause(field: .createdAt, op: .before, value: .relativeDate(.today)))
        #expect(result.dropped.isEmpty)
        #expect(result.group.predicates == [.leaf(Leaf(field: .createdAt, op: .before, value: .relativeDate(.today)))])
    }

    @Test("'in the past' has no dedicated operator — expressed as before(.today)")
    func inThePastIdiom() {
        let result = map(IntermediateClause(field: .deadline, op: .before, value: .relativeDate(.today)))
        #expect(result.group.predicates == [.leaf(Leaf(field: .deadline, op: .before, value: .relativeDate(.today)))])
    }

    @Test("date fields support before/after/on with a valid ISO-8601 absolute date")
    func dateAbsoluteValid() throws {
        let result = map(IntermediateClause(field: .deadline, op: .before, value: .absoluteDateISO8601("2026-07-20")))
        #expect(result.dropped.isEmpty)
        guard case .leaf(let leaf)? = result.group.predicates.first,
              case .absoluteDate(let d) = leaf.value else {
            Issue.record("expected an absoluteDate leaf")
            return
        }
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: d)
        #expect(comps.year == 2026 && comps.month == 7 && comps.day == 20)
    }

    @Test("an unparsable absolute date string drops the clause with the string preserved")
    func dateAbsoluteInvalid() {
        let result = map(IntermediateClause(field: .deadline, op: .before, value: .absoluteDateISO8601("not-a-date")))
        #expect(result.dropped == [DroppedClause(field: .deadline, op: .before, reason: .invalidDate("not-a-date"))])
        #expect(result.group.predicates.isEmpty)
    }

    @Test("date fields support withinLastDays/withinNextDays with a non-negative day count")
    func dateWindow() {
        for op in [Op.withinLastDays, .withinNextDays] {
            let ok = map(IntermediateClause(field: .deadline, op: op, value: .dayCount(7)))
            #expect(ok.dropped.isEmpty)
            #expect(ok.group.predicates == [.leaf(Leaf(field: .deadline, op: op, value: .dayCount(7)))])

            let negative = map(IntermediateClause(field: .deadline, op: op, value: .dayCount(-1)))
            #expect(negative.dropped == [DroppedClause(field: .deadline, op: op, reason: .wrongValueKind)])
        }
    }

    @Test("date fields support isSet/isUnset regardless of value payload")
    func dateSetUnset() {
        for op in [Op.isSet, .isUnset] {
            let result = map(IntermediateClause(field: .start, op: op, value: .none))
            #expect(result.dropped.isEmpty)
            #expect(result.group.predicates == [.leaf(Leaf(field: .start, op: op, value: .bool(true)))])
        }
    }

    @Test("equalsModifiedAt is createdAt-only")
    func equalsModifiedAtCreatedAtOnly() {
        let ok = map(IntermediateClause(field: .createdAt, op: .equalsModifiedAt, value: .none))
        #expect(ok.dropped.isEmpty)
        #expect(ok.group.predicates == [.leaf(Leaf(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))])

        let bad = map(IntermediateClause(field: .modifiedAt, op: .equalsModifiedAt, value: .none))
        #expect(bad.dropped == [DroppedClause(field: .modifiedAt, op: .equalsModifiedAt, reason: .offMatrix)])
    }

    @Test("date field with an illegal op is off-matrix")
    func dateIllegalOp() {
        let result = map(IntermediateClause(field: .deadline, op: .includesAny, value: .relativeDate(.today)))
        #expect(result.dropped == [DroppedClause(field: .deadline, op: .includesAny, reason: .offMatrix)])
    }

    @Test("date field with a mismatched value kind is wrongValueKind")
    func dateWrongValueKind() {
        let result = map(IntermediateClause(field: .deadline, op: .before, value: .text("today")))
        #expect(result.dropped == [DroppedClause(field: .deadline, op: .before, reason: .wrongValueKind)])
    }

    // MARK: - hasAttachments

    @Test("hasAttachments supports only `is`")
    func hasAttachmentsLegal() {
        let match = AttachmentKindMatch(present: true, kind: .image)
        let ok = map(IntermediateClause(field: .hasAttachments, op: .is, value: .attachmentKind(match)))
        #expect(ok.group.predicates == [.leaf(Leaf(field: .hasAttachments, op: .is, value: .attachmentKind(match)))])

        let bad = map(IntermediateClause(field: .hasAttachments, op: .contains, value: .attachmentKind(match)))
        #expect(bad.dropped == [DroppedClause(field: .hasAttachments, op: .contains, reason: .offMatrix)])
    }

    // MARK: - ancestor (always off-matrix — no surfaced NL phrase, matches the engine's isAncestorOf stub)

    @Test("ancestor is always off-matrix from a translator")
    func ancestorAlwaysOffMatrix() {
        for op in [Op.isDescendantOf, .isAncestorOf] {
            let result = map(IntermediateClause(field: .ancestor, op: op, value: .tagNames(["x"])))
            #expect(result.dropped == [DroppedClause(field: .ancestor, op: op, reason: .offMatrix)])
        }
    }

    // MARK: - combinators / composite queries

    @Test("'has due date in the past and is incomplete' — the issue's compound example, AND-combined")
    func compoundIssueExample() {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .deadline, op: .before, value: .relativeDate(.today)),
            IntermediateClause(field: .status, op: .isNot, value: .statuses([.closed]))
        ])
        let result = IntermediateFilterMapper.map(filter, context: Self.ctx)
        #expect(result.dropped.isEmpty)
        #expect(result.group.combinator == .all)
        #expect(result.group.predicates == [
            .leaf(Leaf(field: .deadline, op: .before, value: .relativeDate(.today))),
            .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
        ])
    }

    @Test("a good clause survives alongside a dropped one — per-clause tolerance")
    func perClauseTolerance() {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .createdAt, op: .before, value: .relativeDate(.today)),
            IntermediateClause(field: .journalText, op: .equals, value: .text("nope")) // off-matrix
        ])
        let result = IntermediateFilterMapper.map(filter, context: Self.ctx)
        #expect(result.group.predicates == [.leaf(Leaf(field: .createdAt, op: .before, value: .relativeDate(.today)))])
        #expect(result.dropped == [DroppedClause(field: .journalText, op: .equals, reason: .offMatrix)])
        #expect(!result.isEmpty)
    }

    @Test("every clause dropped yields an empty result — the 'couldn't understand' signal")
    func allDroppedIsEmpty() {
        let filter = IntermediateFilter(combinator: .all, clauses: [
            IntermediateClause(field: .journalText, op: .equals, value: .text("nope")),
            IntermediateClause(field: .ancestor, op: .isDescendantOf, value: .none)
        ])
        let result = IntermediateFilterMapper.map(filter, context: Self.ctx)
        #expect(result.group.predicates.isEmpty)
        #expect(result.isEmpty)
        #expect(result.dropped.count == 2)
    }

    @Test("no clauses at all yields an empty (matches-everything-non-trashed) group, not a crash")
    func noClauses() {
        let result = IntermediateFilterMapper.map(IntermediateFilter(combinator: .all, clauses: []), context: Self.ctx)
        #expect(result.group.predicates.isEmpty)
        #expect(result.isEmpty)
        #expect(result.dropped.isEmpty)
    }

    @Test("mapping is deterministic — repeated mapping of the same input is byte-identical")
    func deterministic() {
        let filter = IntermediateFilter(combinator: .any, clauses: [
            IntermediateClause(field: .tag, op: .includesAny, value: .tagNames(["Home", "Work", "Nonexistent"]))
        ])
        let first = IntermediateFilterMapper.map(filter, context: Self.ctx)
        let second = IntermediateFilterMapper.map(filter, context: Self.ctx)
        #expect(first == second)
    }
}
