import Foundation

/// A tag as loaded from the store, before tree-flattening.
///
/// The app-target wrappers map `TagStore.TagRecord` — which has no public init
/// and so can't be constructed in tests or outside `LillistCore` — into this
/// LillistUI-local value, then call ``TagNode/flatten(_:)`` to produce the
/// depth-indented display list. Keeping the presenter on a LillistUI-owned DTO
/// is what makes it unit-testable with mock data.
public struct FlatTagInput: Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tintHex: String?
    public let parentID: UUID?
    public let position: Double

    public init(id: UUID, name: String, tintHex: String?, parentID: UUID?, position: Double) {
        self.id = id
        self.name = name
        self.tintHex = tintHex
        self.parentID = parentID
        self.position = position
    }
}

/// One row in the tag-management list: a tag plus its computed tree position.
public struct TagNode: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tintHex: String?
    /// Indentation level; `0` for root tags.
    public let depth: Int
    /// Descendant tags a delete would cascade-remove (`Tag.children` is
    /// `Cascade`). Drives the delete-confirmation copy.
    public let descendantCount: Int

    public init(id: UUID, name: String, tintHex: String?, depth: Int, descendantCount: Int) {
        self.id = id
        self.name = name
        self.tintHex = tintHex
        self.depth = depth
        self.descendantCount = descendantCount
    }
}

public extension TagNode {
    /// Flatten a set of tags into a depth-ordered, pre-order (parent-before-child)
    /// display list.
    ///
    /// Siblings are ordered by `position`, then case-insensitive `name` as a
    /// stable tiebreak. Tags whose `parentID` matches no supplied tag are treated
    /// as roots, so nothing is ever hidden from management. `descendantCount` is
    /// the full subtree size minus the node itself — the number a cascade delete
    /// removes. Assumes an acyclic input (`TagStore` rejects parent cycles).
    nonisolated static func flatten(_ inputs: [FlatTagInput]) -> [TagNode] {
        guard !inputs.isEmpty else { return [] }
        let knownIDs = Set(inputs.map(\.id))
        var childrenByParent: [UUID: [FlatTagInput]] = [:]
        var roots: [FlatTagInput] = []
        for input in inputs {
            if let parent = input.parentID, knownIDs.contains(parent) {
                childrenByParent[parent, default: []].append(input)
            } else {
                roots.append(input)
            }
        }

        func before(_ a: FlatTagInput, _ b: FlatTagInput) -> Bool {
            if a.position != b.position { return a.position < b.position }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        var subtreeSize: [UUID: Int] = [:]
        func size(of input: FlatTagInput) -> Int {
            if let cached = subtreeSize[input.id] { return cached }
            let total = 1 + (childrenByParent[input.id] ?? []).reduce(0) { $0 + size(of: $1) }
            subtreeSize[input.id] = total
            return total
        }

        var result: [TagNode] = []
        func visit(_ input: FlatTagInput, depth: Int) {
            result.append(TagNode(
                id: input.id,
                name: input.name,
                tintHex: input.tintHex,
                depth: depth,
                descendantCount: size(of: input) - 1
            ))
            for child in (childrenByParent[input.id] ?? []).sorted(by: before) {
                visit(child, depth: depth + 1)
            }
        }
        for root in roots.sorted(by: before) {
            visit(root, depth: 0)
        }
        return result
    }
}

/// One row in the saved-filter-management list.
public struct SavedFilterRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tintHex: String?
    public let isPinned: Bool

    public init(id: UUID, name: String, tintHex: String?, isPinned: Bool) {
        self.id = id
        self.name = name
        self.tintHex = tintHex
        self.isPinned = isPinned
    }
}

/// The item currently being edited on the Tags & Filters screen — drives the
/// `.sheet(item:)` hosted by each platform's page/pane container (never on the
/// `Section` itself; see `ICloudSyncSection`).
public enum TagsFiltersEditRoute: Identifiable {
    case tag(TagNode)
    case filter(SavedFilterRow)

    public var id: UUID {
        switch self {
        case .tag(let node): return node.id
        case .filter(let row): return row.id
        }
    }
}

/// Loads a full tag tree via a caller-supplied `fetchChildren` closure and returns
/// the flattened display list. The closure keeps `LillistUI` free of `LillistCore`
/// store types: each app wrapper adapts `TagStore.children(of:)` into
/// ``FlatTagInput`` values. Shared so iOS and macOS don't each re-implement the
/// recursion.
///
/// `@MainActor`-isolated: the `fetchChildren` closure captures each wrapper's
/// MainActor `AppEnvironment` (non-`Sendable`), so the loader must share that
/// isolation rather than "send" the closure to a nonisolated executor.
public enum TagTreeLoader {
    @MainActor
    public static func flattenedTags(
        fetchChildren: (UUID?) async throws -> [FlatTagInput]
    ) async throws -> [TagNode] {
        var all: [FlatTagInput] = []
        func gather(_ parent: UUID?) async throws {
            for input in try await fetchChildren(parent) {
                all.append(input)
                try await gather(input.id)
            }
        }
        try await gather(nil)
        return TagNode.flatten(all)
    }
}

/// Pure name-validity check shared by both editor sheets (and their tests):
/// a name must be non-empty after trimming whitespace, matching the store guards
/// (`TagStore`/`SmartFilterStore` reject empty names with `validationFailed`).
public enum TagsFiltersEditing {
    public nonisolated static func isNameValid(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The trimmed value that should be sent to the store on save.
    public nonisolated static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
