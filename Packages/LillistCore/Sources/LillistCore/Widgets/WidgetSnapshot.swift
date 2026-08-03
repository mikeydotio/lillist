import Foundation

/// Compact, `Codable` description of one smart filter's contents for the widget
/// extension. Written to the App Group container by the app/extensions
/// (``WidgetSnapshotBuilder``) and read by the widget's timeline provider — so
/// the widget never spins up the Core Data stack on its fast path.
///
/// **Pure Foundation — never import WidgetKit here.** `LillistCore` is linked by
/// the headless `lillist-cli`, which cannot link WidgetKit. See the
/// WidgetKit-not-in-Core rule in `CLAUDE.md` / `docs/engineering-notes.md`.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// One task row. `LIL-95` added the three trailing fields so the widget can
    /// render a correct outline instead of a flat peer list.
    public struct Row: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var status: Status
        /// This task's true parent, regardless of whether that parent is
        /// itself on the card. `nil` for a root task. Drives whether a row
        /// needs the "parent not shown here" marker (``WidgetRowPlan``).
        public var parentID: UUID?
        /// Display indent tier, already clamped to `0...2` by
        /// ``WidgetSnapshotBuilder`` — a depth-3+ descendant renders at tier 2
        /// rather than continuing to indent.
        public var depth: Int
        /// `true` when this row is a non-matching parent rendered only so its
        /// matching descendants have somewhere to nest — dimmed and
        /// non-interactive. Never counted in `totalCount`/`openCount`.
        public var isContext: Bool

        public init(
            id: UUID,
            title: String,
            status: Status,
            parentID: UUID? = nil,
            depth: Int = 0,
            isContext: Bool = false
        ) {
            self.id = id
            self.title = title
            self.status = status
            self.parentID = parentID
            self.depth = depth
            self.isContext = isContext
        }

        // Hand-written `init(from:)` so a pre-`LIL-95` cache file — written
        // before `parentID`/`depth`/`isContext` existed — decodes cleanly
        // instead of throwing `keyNotFound` (which `WidgetSnapshotStore.read`
        // would otherwise swallow into an indistinguishable-from-missing
        // `nil`). Swift's synthesized `init(from:)` does NOT fall back to a
        // property's default when a key is absent, so this must be explicit.
        // `encode(to:)` stays synthesized — every field always exists on
        // write, so a matching `CodingKeys` here just documents that.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            status = try c.decode(Status.self, forKey: .status)
            parentID = try c.decodeIfPresent(UUID.self, forKey: .parentID)
            depth = try c.decodeIfPresent(Int.self, forKey: .depth) ?? 0
            isContext = try c.decodeIfPresent(Bool.self, forKey: .isContext) ?? false
        }

        private enum CodingKeys: String, CodingKey {
            case id, title, status, parentID, depth, isContext
        }
    }

    /// Reserved id for the "No Filter" (unfiltered — all tasks) state. A fresh
    /// widget defaults to this; it is never a real `SmartFilter.id` (Core Data
    /// mints v4 UUIDs, never the all-zero one). Shared source of truth for the
    /// widget config entity, the timeline provider, the snapshot builder, and the
    /// header (which hides the name for this id).
    public static let unfilteredID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Whether this snapshot represents the unfiltered "all tasks" view rather
    /// than a saved smart filter.
    public var isUnfiltered: Bool { filterID == Self.unfilteredID }

    /// Identity of the source smart filter.
    public var filterID: UUID
    /// User-facing filter name, rendered in the widget header.
    public var filterName: String
    /// Optional filter tint (hex string, as stored on `SmartFilterRecord.tintColor`).
    public var tintHex: String?
    /// When this snapshot was produced (for staleness display / debugging).
    public var generatedAt: Date
    /// Total number of tasks matching the filter (may exceed `tasks.count`).
    public var totalCount: Int
    /// Number of matching tasks that are not yet closed ("remaining").
    public var openCount: Int
    /// The (capped) task rows to render, in the filter's sort order.
    public var tasks: [Row]

    public init(
        filterID: UUID,
        filterName: String,
        tintHex: String?,
        generatedAt: Date,
        totalCount: Int,
        openCount: Int,
        tasks: [Row]
    ) {
        self.filterID = filterID
        self.filterName = filterName
        self.tintHex = tintHex
        self.generatedAt = generatedAt
        self.totalCount = totalCount
        self.openCount = openCount
        self.tasks = tasks
    }
}

/// Lightweight listing of the available filters, written alongside the per-filter
/// snapshots. Lets the widget resolve a configured filter's display name before
/// its snapshot exists, and backs the configuration picker when a direct store
/// read isn't desirable.
public struct WidgetSnapshotIndex: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var tintHex: String?

        public init(id: UUID, name: String, tintHex: String?) {
            self.id = id
            self.name = name
            self.tintHex = tintHex
        }
    }

    public var filters: [Entry]
    public var generatedAt: Date

    public init(filters: [Entry], generatedAt: Date) {
        self.filters = filters
        self.generatedAt = generatedAt
    }
}
