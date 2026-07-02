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
    /// One task row. Minimal on purpose — title + status drive the glyph.
    public struct Row: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var status: Status

        public init(id: UUID, title: String, status: Status) {
            self.id = id
            self.title = title
            self.status = status
        }
    }

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
