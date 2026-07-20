import Foundation

/// Renders a `PredicateGroup` back into a short, deterministic English
/// summary — "created before today", "deadline in the past and status is
/// not closed" — so the smart-search UI can show the user what their query
/// was actually interpreted as. Deliberately generic (works for any
/// `PredicateGroup`, not just translator output) and covers the common
/// field/op/value shapes the rule engine supports; an unrecognized
/// combination is simply omitted rather than guessed at.
public enum PredicateGroupExplainer {
    public static func explain(_ group: PredicateGroup) -> String? {
        guard !group.predicates.isEmpty else { return nil }
        let joiner = group.combinator == .all ? " and " : " or "
        let parts = group.predicates.compactMap(explain(predicate:))
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: joiner)
    }

    private static func explain(predicate: Predicate) -> String? {
        switch predicate {
        case .leaf(let leaf): return explain(leaf: leaf)
        case .group(let g):
            guard let inner = explain(g) else { return nil }
            return "(\(inner))"
        }
    }

    private static func explain(leaf: Leaf) -> String? {
        let name = fieldLabel(leaf.field)
        switch (leaf.op, leaf.value) {
        case (.contains, .string(let s)): return "\(name) contains “\(s)”"
        case (.equals, .string(let s)): return "\(name) is “\(s)”"
        case (.startsWith, .string(let s)): return "\(name) starts with “\(s)”"

        case (.is, .statusSet(let set)) where leaf.field == .status:
            return "status is \(statusList(set))"
        case (.isNot, .statusSet(let set)) where leaf.field == .status:
            return "status is not \(statusList(set))"

        case (.before, .relativeDate(let r)): return "\(name) before \(relativeLabel(r))"
        case (.after, .relativeDate(let r)): return "\(name) after \(relativeLabel(r))"
        case (.on, .relativeDate(let r)): return "\(name) on \(relativeLabel(r))"
        case (.before, .absoluteDate(let d)): return "\(name) before \(dateLabel(d))"
        case (.after, .absoluteDate(let d)): return "\(name) after \(dateLabel(d))"
        case (.on, .absoluteDate(let d)): return "\(name) on \(dateLabel(d))"

        case (.withinLastDays, .dayCount(let n)): return "\(name) within the last \(dayLabel(n))"
        case (.withinNextDays, .dayCount(let n)): return "\(name) within the next \(dayLabel(n))"

        case (.isSet, _) where leaf.field != .tag: return "\(name) is set"
        case (.isUnset, _) where leaf.field != .tag: return "\(name) is not set"
        case (.isSet, _) where leaf.field == .tag: return "has tags"
        case (.isUnset, _) where leaf.field == .tag: return "has no tags"

        case (.equalsModifiedAt, _) where leaf.field == .createdAt: return "never edited"

        case (.includesAny, .uuidSet(let ids)): return "tagged with any of \(tagCount(ids.count))"
        case (.includesAll, .uuidSet(let ids)): return "tagged with all of \(tagCount(ids.count))"
        case (.excludesAll, .uuidSet(let ids)): return "not tagged with any of \(tagCount(ids.count))"

        case (.is, .bool(let b)) where leaf.field == .isPinned: return b ? "pinned" : "not pinned"
        case (.is, .bool(let b)) where leaf.field == .hasChildren: return b ? "has subtasks" : "has no subtasks"
        case (.is, .bool(let b)) where leaf.field == .hasNudges: return b ? "has reminders" : "has no reminders"
        case (.is, .bool(let b)) where leaf.field == .recurrence: return b ? "recurring" : "not recurring"
        case (.is, .bool(let b)) where leaf.field == .inTrash: return b ? "in Trash" : "not in Trash"

        case (.is, .attachmentKind(let match)):
            return match.present ? "has attachments" : "has no attachments"

        default:
            return nil
        }
    }

    private static func fieldLabel(_ field: Field) -> String {
        switch field {
        case .title: return "title"
        case .notes: return "notes"
        case .journalText: return "journal"
        case .tag: return "tag"
        case .status: return "status"
        case .start: return "start"
        case .deadline: return "deadline"
        case .createdAt: return "created"
        case .modifiedAt: return "modified"
        case .closedAt: return "closed"
        case .hasAttachments: return "attachments"
        case .hasChildren: return "subtasks"
        case .hasNudges: return "reminders"
        case .isPinned: return "pinned"
        case .ancestor: return "location"
        case .recurrence: return "recurrence"
        case .inTrash: return "trash"
        }
    }

    private static func statusList(_ set: Set<Status>) -> String {
        set.map(\.label).sorted().joined(separator: ", ")
    }

    private static func relativeLabel(_ r: RelativeDate) -> String {
        switch r {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .yesterday: return "yesterday"
        case .daysFromNow(let n): return n == 0 ? "today" : "\(n > 0 ? "+" : "")\(n) day\(abs(n) == 1 ? "" : "s")"
        case .weeksFromNow(let n): return n == 0 ? "this week" : "\(n > 0 ? "+" : "")\(n) week\(abs(n) == 1 ? "" : "s")"
        case .startOfWeek: return "the start of the week"
        case .endOfWeek: return "the end of the week"
        case .startOfMonth: return "the start of the month"
        case .endOfMonth: return "the end of the month"
        }
    }

    private static func dateLabel(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: d)
    }

    private static func dayLabel(_ n: Int) -> String {
        "\(n) day\(n == 1 ? "" : "s")"
    }

    private static func tagCount(_ n: Int) -> String {
        "\(n) tag\(n == 1 ? "" : "s")"
    }
}

private extension Status {
    var label: String {
        switch self {
        case .todo: return "to-do"
        case .started: return "started"
        case .blocked: return "blocked"
        case .closed: return "closed"
        }
    }
}
