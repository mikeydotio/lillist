import Foundation

/// Reads/writes ``WidgetSnapshot`` JSON in the App Group container so the widget
/// extension can render without opening Core Data.
///
/// On-disk layout (sibling to the store's `Lillist/Lillist.sqlite`):
/// ```
/// <group container>/Widget/index.json
/// <group container>/Widget/filters/<filterID>.json
/// ```
///
/// **Pure Foundation — no WidgetKit.** Safe to link from `lillist-cli`.
public struct WidgetSnapshotStore: Sendable {
    private let root: URL

    /// Production initializer. Returns `nil` when the App Group container is not
    /// reachable (entitlement missing or running outside a signed sandbox) —
    /// mirrors ``StoreConfiguration/appGroupOnDisk(groupID:syncMode:)``.
    public init?(appGroupID: String) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        self.root = container.appendingPathComponent("Widget", isDirectory: true)
    }

    /// Test seam: point the store at an arbitrary directory (no App Group needed).
    public init(rootDirectory: URL) {
        self.root = rootDirectory
    }

    private var filtersDirectory: URL {
        root.appendingPathComponent("filters", isDirectory: true)
    }

    private func snapshotURL(filterID: UUID) -> URL {
        filtersDirectory
            .appendingPathComponent(filterID.uuidString, isDirectory: false)
            .appendingPathExtension("json")
    }

    private var indexURL: URL {
        root.appendingPathComponent("index", isDirectory: false)
            .appendingPathExtension("json")
    }

    // MARK: - Per-filter snapshot

    public func write(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(at: filtersDirectory, withIntermediateDirectories: true)
        try Self.encode(snapshot).write(to: snapshotURL(filterID: snapshot.filterID), options: .atomic)
    }

    public func read(filterID: UUID) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL(filterID: filterID)) else { return nil }
        return try? Self.decode(WidgetSnapshot.self, from: data)
    }

    // MARK: - Index

    public func writeIndex(_ index: WidgetSnapshotIndex) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.encode(index).write(to: indexURL, options: .atomic)
    }

    public func readIndex() -> WidgetSnapshotIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? Self.decode(WidgetSnapshotIndex.self, from: data)
    }

    // MARK: - Maintenance

    /// Remove per-filter snapshot files whose filter no longer exists, so a
    /// deleted filter's stale cache can't be served to a widget still pointed at
    /// it. Best-effort; failures are ignored.
    public func pruneFilters(keeping ids: Set<UUID>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: filtersDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  ids.contains(id) == false
            else { continue }
            try? fm.removeItem(at: file)
        }
    }

    // MARK: - Coders

    // Fresh coders per call: a `static let JSONEncoder` would trip strict
    // concurrency (JSONEncoder isn't Sendable). Widget writes are debounced and
    // reads happen a handful of times per refresh, so the allocation is noise.
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
