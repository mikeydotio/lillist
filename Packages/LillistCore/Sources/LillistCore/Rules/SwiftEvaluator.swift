import Foundation
import CoreData

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
        case .start: return matchDate(s.start, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .deadline: return matchDate(s.deadline, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .createdAt: return matchDate(s.createdAt, otherDate: s.modifiedAt, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .modifiedAt: return matchDate(s.modifiedAt, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .closedAt: return matchDate(s.closedAt, otherDate: nil, op: leaf.op, value: leaf.value, now: now, calendar: calendar)
        case .tag: return matchTag(s.tagIDs, op: leaf.op, value: leaf.value)
        case .ancestor: return matchAncestor(s.ancestorIDs, op: leaf.op, value: leaf.value)
        case .journalText: return matchJournalText(s.journalNoteBodies, op: leaf.op, value: leaf.value)
        case .hasAttachments: return matchHasAttachments(s.attachmentKinds, op: leaf.op, value: leaf.value)
        }
    }

    // MARK: - Relational matchers

    static func matchTag(_ tagIDs: Set<UUID>, op: Op, value: Value) -> Bool {
        // `isSet` / `isUnset` ask about cardinality, not membership — handle
        // them before the `uuidSet` guard so parity with `compileTag` is
        // preserved for the "No Tags" default smart filter.
        switch op {
        case .isUnset: return tagIDs.isEmpty
        case .isSet: return !tagIDs.isEmpty
        default: break
        }
        guard case .uuidSet(let ids) = value else { return false }
        switch op {
        case .includesAny: return !tagIDs.isDisjoint(with: ids)
        case .includesAll: return ids.isSubset(of: tagIDs)
        case .excludesAll: return tagIDs.isDisjoint(with: ids)
        default: return false
        }
    }

    static func matchAncestor(_ ancestorIDs: Set<UUID>, op: Op, value: Value) -> Bool {
        guard case .uuidSet(let ids) = value else { return false }
        switch op {
        case .isDescendantOf: return !ancestorIDs.isDisjoint(with: ids)
        case .isAncestorOf:
            // Symmetry: a snapshot of an ancestor task has the descendant ids
            // in `ancestorIDs`? No — `isAncestorOf` asks "is THIS task an
            // ancestor of any of the given ids?" That requires the caller
            // to supply descendant-id reachability; not represented in the
            // snapshot today. Return false; the parity suite excludes this
            // op for SwiftEvaluator until a snapshot extension is added.
            return false
        default: return false
        }
    }

    static func matchJournalText(_ bodies: [String], op: Op, value: Value) -> Bool {
        guard op == .contains, case .string(let needle) = value else { return false }
        return bodies.contains { $0.localizedStandardContains(needle) }
    }

    static func matchHasAttachments(_ kinds: [AttachmentKind], op: Op, value: Value) -> Bool {
        guard op == .is, case .attachmentKind(let match) = value else { return false }
        let pool: [AttachmentKind]
        if let kindFilter = match.kind {
            pool = kinds.filter { $0 == kindFilter }
        } else {
            pool = kinds
        }
        return match.present ? !pool.isEmpty : pool.isEmpty
    }

    // MARK: - Date matcher

    static func matchDate(
        _ date: Date?,
        otherDate: Date?,
        op: Op,
        value: Value,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        switch op {
        case .isSet: return date != nil
        case .isUnset: return date == nil
        case .equalsModifiedAt:
            guard let a = date, let b = otherDate else { return false }
            return a == b
        case .before, .after, .on:
            guard let actual = date,
                  let target = resolveAbsolute(value, now: now, calendar: calendar) else {
                return false
            }
            switch op {
            case .before: return actual < target
            case .after: return actual > target
            case .on:
                let startOfDay = calendar.startOfDay(for: target)
                let endOfDay = RelativeDateResolver.endOfDay(for: startOfDay, calendar: calendar)
                return actual >= startOfDay && actual <= endOfDay
            default: return false
            }
        case .withinLastDays:
            guard let actual = date, case .dayCount(let n) = value else { return false }
            let startOfToday = calendar.startOfDay(for: now)
            let cutoff = calendar.date(byAdding: .day, value: -n, to: startOfToday) ?? startOfToday
            return actual >= cutoff && actual <= now
        case .withinNextDays:
            guard let actual = date, case .dayCount(let n) = value else { return false }
            let startOfToday = calendar.startOfDay(for: now)
            let horizon = calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
            let horizonEnd = RelativeDateResolver.endOfDay(for: horizon, calendar: calendar)
            return actual >= now && actual <= horizonEnd
        default: return false
        }
    }

    static func resolveAbsolute(_ value: Value, now: Date, calendar: Calendar) -> Date? {
        switch value {
        case .absoluteDate(let d): return d
        case .relativeDate(let r): return RelativeDateResolver.resolve(r, now: now, calendar: calendar)
        default: return nil
        }
    }

    // MARK: - Primitive matchers (slice 1)

    static func matchString(_ haystack: String, op: Op, value: Value) -> Bool {
        guard case .string(let needle) = value else { return false }
        switch op {
        case .contains: return haystack.localizedStandardContains(needle)
        case .equals:
            // Match the compiler's `==[cd]`: case- AND diacritic-insensitive.
            return haystack.compare(
                needle,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: nil
            ) == .orderedSame
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

extension SwiftEvaluator.TaskSnapshot {
    /// Build a snapshot from a fetched `LillistTask`. Caller must invoke
    /// inside the managed object's context (via `context.perform`) to
    /// safely touch relationships.
    public static func from(managedObject m: LillistTask) -> SwiftEvaluator.TaskSnapshot {
        // Tag ids
        let tagIDs: Set<UUID> = {
            guard let tags = m.tags as? Set<Tag> else { return [] }
            return Set(tags.compactMap { $0.id })
        }()
        // Ancestor chain, depth-bounded by the shared `PredicateLimits`
        // ceiling so this walk matches `NSPredicateCompiler.compileAncestor`.
        var ancestorIDs: Set<UUID> = []
        var cursor: LillistTask? = m.parent
        var depth = 0
        while let p = cursor, depth < PredicateLimits.maxAncestorDepth {
            if let pid = p.id { ancestorIDs.insert(pid) }
            cursor = p.parent
            depth += 1
        }
        // Journal note bodies
        let noteBodies: [String] = {
            guard let entries = m.journalEntries as? Set<JournalEntry> else { return [] }
            return entries
                .filter { $0.kind == .note }
                .compactMap { $0.body }
        }()
        // Attachment kinds
        let kinds: [AttachmentKind] = {
            guard let attachments = m.attachments as? Set<Attachment> else { return [] }
            return attachments.map { $0.kind }
        }()
        let childCount: Int = (m.children as? Set<LillistTask>)?.count ?? 0
        return SwiftEvaluator.TaskSnapshot(
            id: m.id ?? UUID(),
            title: m.title ?? "",
            notes: m.notes ?? "",
            status: m.status,
            start: m.start, startHasTime: m.startHasTime,
            deadline: m.deadline, deadlineHasTime: m.deadlineHasTime,
            createdAt: m.createdAt ?? Date(),
            modifiedAt: m.modifiedAt ?? Date(),
            closedAt: m.closedAt,
            isPinned: m.isPinned,
            inTrash: m.deletedAt != nil,
            hasChildren: childCount > 0,
            childCount: childCount,
            tagIDs: tagIDs,
            ancestorIDs: ancestorIDs,
            journalNoteBodies: noteBodies,
            attachmentKinds: kinds,
            hasNudges: (m.notificationSpecs?.count ?? 0) > 0,
            isRecurring: m.series != nil
        )
    }
}
