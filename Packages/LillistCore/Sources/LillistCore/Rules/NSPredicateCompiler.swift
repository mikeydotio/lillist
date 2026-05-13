import Foundation
import CoreData

/// Translates a `PredicateGroup` into an `NSPredicate` over the `LillistTask`
/// entity. The compiled predicate is suitable for `NSFetchRequest.predicate`
/// and `NSFetchedResultsController`.
///
/// The implicit-trash rule (design Section 5): unless the group contains a
/// leaf with `field == .inTrash`, the compiled top-level predicate
/// conjoins `deletedAt == nil` so smart filters never surface Trash.
public enum NSPredicateCompiler {
    /// Top-level entry point. `now` and `calendar` are used to resolve
    /// `RelativeDate` values at compile time. Callers wishing live-updating
    /// "rolling 7 days" semantics must recompile on a timer (handled by the
    /// SmartFilter view layer in later plans).
    public static func compile(
        _ group: PredicateGroup,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NSPredicate {
        let base = compileGroup(group, now: now, calendar: calendar)
        if containsField(.inTrash, in: group) {
            return base
        }
        let trashFilter = NSPredicate(format: "deletedAt == nil")
        return NSCompoundPredicate(andPredicateWithSubpredicates: [base, trashFilter])
    }

    static func compileGroup(
        _ group: PredicateGroup,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        if group.predicates.isEmpty {
            return NSPredicate(value: true)
        }
        let subs = group.predicates.map { compilePredicate($0, now: now, calendar: calendar) }
        switch group.combinator {
        case .all: return NSCompoundPredicate(andPredicateWithSubpredicates: subs)
        case .any: return NSCompoundPredicate(orPredicateWithSubpredicates: subs)
        }
    }

    static func compilePredicate(
        _ predicate: Predicate,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        switch predicate {
        case .leaf(let leaf):
            return compileLeaf(leaf, now: now, calendar: calendar)
        case .group(let g):
            return compileGroup(g, now: now, calendar: calendar)
        }
    }

    static func compileLeaf(
        _ leaf: Leaf,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        switch leaf.field {
        case .title: return compileString(keyPath: "title", op: leaf.op, value: leaf.value)
        case .notes: return compileString(keyPath: "notes", op: leaf.op, value: leaf.value)
        case .status: return compileStatus(op: leaf.op, value: leaf.value)
        case .isPinned: return compileBool(keyPath: "isPinned", op: leaf.op, value: leaf.value)
        case .inTrash: return compileInTrash(op: leaf.op, value: leaf.value)
        case .hasChildren: return compileHasChildren(op: leaf.op, value: leaf.value)

        case .start, .deadline, .createdAt, .modifiedAt, .closedAt:
            return compileDate(field: leaf.field, op: leaf.op, value: leaf.value, now: now, calendar: calendar)

        case .hasAttachments:
            return compileHasAttachments(op: leaf.op, value: leaf.value)

        case .journalText:
            return compileJournalText(op: leaf.op, value: leaf.value)

        case .tag:
            return compileTag(op: leaf.op, value: leaf.value)

        case .ancestor:
            return compileAncestor(op: leaf.op, value: leaf.value)

        case .hasNudges, .recurrence:
            // Wired up by Plans 4 and 5 respectively.
            return NSPredicate(value: false)
        }
    }

    // MARK: - String

    static func compileString(keyPath: String, op: Op, value: Value) -> NSPredicate {
        guard case .string(let s) = value else { return NSPredicate(value: false) }
        switch op {
        case .contains:
            return NSPredicate(format: "%K CONTAINS[cd] %@", keyPath, s)
        case .equals:
            return NSPredicate(format: "%K ==[cd] %@", keyPath, s)
        case .startsWith:
            return NSPredicate(format: "%K BEGINSWITH[cd] %@", keyPath, s)
        default:
            return NSPredicate(value: false)
        }
    }

    // MARK: - Status

    static func compileStatus(op: Op, value: Value) -> NSPredicate {
        guard case .statusSet(let set) = value else { return NSPredicate(value: false) }
        let raws = set.map { Int16($0.rawValue) } as [Int16]
        switch op {
        case .is: return NSPredicate(format: "statusRaw IN %@", raws)
        case .isNot: return NSPredicate(format: "NOT (statusRaw IN %@)", raws)
        default: return NSPredicate(value: false)
        }
    }

    // MARK: - Bool

    static func compileBool(keyPath: String, op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return NSPredicate(format: "%K == %@", keyPath, NSNumber(value: b))
    }

    // MARK: - inTrash

    static func compileInTrash(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "deletedAt != nil")
            : NSPredicate(format: "deletedAt == nil")
    }

    // MARK: - hasChildren

    static func compileHasChildren(op: Op, value: Value) -> NSPredicate {
        guard case .bool(let b) = value, op == .is else { return NSPredicate(value: false) }
        return b
            ? NSPredicate(format: "children.@count > 0")
            : NSPredicate(format: "children.@count == 0")
    }

    // MARK: - Dates

    static func compileDate(
        field: Field,
        op: Op,
        value: Value,
        now: Date,
        calendar: Calendar
    ) -> NSPredicate {
        let keyPath = field.rawValue // matches Core Data attribute name
        switch op {
        case .before:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            return NSPredicate(format: "%K < %@", keyPath, d as NSDate)
        case .after:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            return NSPredicate(format: "%K > %@", keyPath, d as NSDate)
        case .on:
            guard let d = resolveAbsolute(value, now: now, calendar: calendar) else {
                return NSPredicate(value: false)
            }
            let startOfDay = calendar.startOfDay(for: d)
            let endOfDay = RelativeDateResolver.endOfDay(for: startOfDay, calendar: calendar)
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, startOfDay as NSDate, keyPath, endOfDay as NSDate)
        case .withinLastDays:
            guard case .dayCount(let n) = value else { return NSPredicate(value: false) }
            let startOfToday = calendar.startOfDay(for: now)
            let cutoff = calendar.date(byAdding: .day, value: -n, to: startOfToday) ?? startOfToday
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, cutoff as NSDate, keyPath, now as NSDate)
        case .withinNextDays:
            guard case .dayCount(let n) = value else { return NSPredicate(value: false) }
            let startOfToday = calendar.startOfDay(for: now)
            let horizon = calendar.date(byAdding: .day, value: n, to: startOfToday) ?? startOfToday
            let horizonEnd = RelativeDateResolver.endOfDay(for: horizon, calendar: calendar)
            return NSPredicate(format: "%K >= %@ AND %K <= %@", keyPath, now as NSDate, keyPath, horizonEnd as NSDate)
        case .isSet:
            return NSPredicate(format: "%K != nil", keyPath)
        case .isUnset:
            return NSPredicate(format: "%K == nil", keyPath)
        case .equalsModifiedAt where field == .createdAt:
            return NSPredicate(format: "createdAt == modifiedAt")
        default:
            return NSPredicate(value: false)
        }
    }

    static func resolveAbsolute(_ value: Value, now: Date, calendar: Calendar) -> Date? {
        switch value {
        case .absoluteDate(let d): return d
        case .relativeDate(let r): return RelativeDateResolver.resolve(r, now: now, calendar: calendar)
        default: return nil
        }
    }

    // MARK: - Attachments

    static func compileHasAttachments(op: Op, value: Value) -> NSPredicate {
        guard case .attachmentKind(let match) = value, op == .is else {
            return NSPredicate(value: false)
        }
        if let kind = match.kind {
            let kindRaw = Int16(kind.rawValue)
            let sub = NSPredicate(format: "SUBQUERY(attachments, $a, $a.kindRaw == %d).@count > 0", kindRaw)
            return match.present ? sub : NSCompoundPredicate(notPredicateWithSubpredicate: sub)
        } else {
            return match.present
                ? NSPredicate(format: "attachments.@count > 0")
                : NSPredicate(format: "attachments.@count == 0")
        }
    }

    // MARK: - Journal text (Task 12 wires up subquery shape)

    static func compileJournalText(op: Op, value: Value) -> NSPredicate {
        return NSPredicate(value: false)
    }

    static func compileTag(op: Op, value: Value) -> NSPredicate {
        return NSPredicate(value: false)
    }

    static func compileAncestor(op: Op, value: Value) -> NSPredicate {
        return NSPredicate(value: false)
    }

    // MARK: - Field-presence check (for implicit trash rule)

    static func containsField(_ target: Field, in group: PredicateGroup) -> Bool {
        for p in group.predicates {
            switch p {
            case .leaf(let l) where l.field == target: return true
            case .group(let g) where containsField(target, in: g): return true
            default: continue
            }
        }
        return false
    }
}
