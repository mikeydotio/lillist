import Foundation

/// Pure-Swift evaluator for a `PredicateGroup`. Operates on a denormalized
/// snapshot so callers can prepare the per-task data however they like
/// (in-memory fetched results, exported records, CLI input). Behavior
/// matches `NSPredicateCompiler` — the parity fixture suite enforces it.
public enum SwiftEvaluator {
    /// Denormalized snapshot of a task. Includes every field the rule engine
    /// might query, including relational fan-outs (tag ids, ancestor ids,
    /// journal note bodies, attachment kinds).
    public struct TaskSnapshot: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var notes: String
        public var status: Status
        public var start: Date?
        public var startHasTime: Bool
        public var deadline: Date?
        public var deadlineHasTime: Bool
        public var createdAt: Date
        public var modifiedAt: Date
        public var closedAt: Date?
        public var isPinned: Bool
        public var inTrash: Bool
        public var hasChildren: Bool
        public var childCount: Int
        public var tagIDs: Set<UUID>
        public var ancestorIDs: Set<UUID>
        public var journalNoteBodies: [String]
        public var attachmentKinds: [AttachmentKind]
        public var hasNudges: Bool
        public var isRecurring: Bool

        public init(
            id: UUID,
            title: String,
            notes: String,
            status: Status,
            start: Date?, startHasTime: Bool,
            deadline: Date?, deadlineHasTime: Bool,
            createdAt: Date, modifiedAt: Date,
            closedAt: Date?,
            isPinned: Bool,
            inTrash: Bool,
            hasChildren: Bool,
            childCount: Int,
            tagIDs: Set<UUID>,
            ancestorIDs: Set<UUID>,
            journalNoteBodies: [String],
            attachmentKinds: [AttachmentKind],
            hasNudges: Bool,
            isRecurring: Bool
        ) {
            self.id = id
            self.title = title
            self.notes = notes
            self.status = status
            self.start = start; self.startHasTime = startHasTime
            self.deadline = deadline; self.deadlineHasTime = deadlineHasTime
            self.createdAt = createdAt; self.modifiedAt = modifiedAt
            self.closedAt = closedAt
            self.isPinned = isPinned
            self.inTrash = inTrash
            self.hasChildren = hasChildren
            self.childCount = childCount
            self.tagIDs = tagIDs
            self.ancestorIDs = ancestorIDs
            self.journalNoteBodies = journalNoteBodies
            self.attachmentKinds = attachmentKinds
            self.hasNudges = hasNudges
            self.isRecurring = isRecurring
        }
    }

    // MARK: - Top-level entry

    public static func evaluate(
        group: PredicateGroup,
        against snapshot: TaskSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        if !NSPredicateCompiler.containsField(.inTrash, in: group), snapshot.inTrash {
            return false
        }
        return evaluateGroup(group, snapshot: snapshot, now: now, calendar: calendar)
    }

    static func evaluateGroup(
        _ group: PredicateGroup,
        snapshot: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        if group.predicates.isEmpty { return true }
        switch group.combinator {
        case .all:
            return group.predicates.allSatisfy {
                evaluatePredicate($0, snapshot: snapshot, now: now, calendar: calendar)
            }
        case .any:
            return group.predicates.contains {
                evaluatePredicate($0, snapshot: snapshot, now: now, calendar: calendar)
            }
        }
    }

    static func evaluatePredicate(
        _ predicate: Predicate,
        snapshot: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch predicate {
        case .leaf(let l): return evaluateLeaf(l, snapshot: snapshot, now: now, calendar: calendar)
        case .group(let g): return evaluateGroup(g, snapshot: snapshot, now: now, calendar: calendar)
        }
    }

    // MARK: - Leaf dispatch (slice 1)

    static func evaluateLeaf(
        _ leaf: Leaf,
        snapshot s: TaskSnapshot,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch leaf.field {
        case .title: return matchString(s.title, op: leaf.op, value: leaf.value)
        case .notes: return matchString(s.notes, op: leaf.op, value: leaf.value)
        case .status: return matchStatus(s.status, op: leaf.op, value: leaf.value)
        case .isPinned: return matchBool(s.isPinned, op: leaf.op, value: leaf.value)
        case .inTrash: return matchBool(s.inTrash, op: leaf.op, value: leaf.value)
        case .hasChildren: return matchBool(s.hasChildren, op: leaf.op, value: leaf.value)
        case .hasNudges: return matchBool(s.hasNudges, op: leaf.op, value: leaf.value)
        case .recurrence: return matchBool(s.isRecurring, op: leaf.op, value: leaf.value)
        // Slice 2 fills the remaining fields.
        default: return false
        }
    }

    // MARK: - Primitive matchers (slice 1)

    static func matchString(_ haystack: String, op: Op, value: Value) -> Bool {
        guard case .string(let needle) = value else { return false }
        switch op {
        case .contains: return haystack.localizedStandardContains(needle)
        case .equals: return haystack.localizedCaseInsensitiveCompare(needle) == .orderedSame
        case .startsWith:
            return haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        default: return false
        }
    }

    static func matchStatus(_ status: Status, op: Op, value: Value) -> Bool {
        guard case .statusSet(let set) = value else { return false }
        switch op {
        case .is: return set.contains(status)
        case .isNot: return !set.contains(status)
        default: return false
        }
    }

    static func matchBool(_ actual: Bool, op: Op, value: Value) -> Bool {
        guard case .bool(let target) = value, op == .is else { return false }
        return actual == target
    }
}
