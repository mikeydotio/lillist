import Testing
import Foundation
@testable import LillistCore

@Suite("WidgetSnapshotStore — JSON round-trip")
struct WidgetSnapshotStoreTests {
    private func tempStore() -> (store: WidgetSnapshotStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        return (WidgetSnapshotStore(rootDirectory: dir), dir)
    }

    private func sampleSnapshot(filterID: UUID = UUID(), rows: Int = 3) -> WidgetSnapshot {
        WidgetSnapshot(
            filterID: filterID,
            filterName: "Todayish",
            tintHex: "#8B45E8",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            totalCount: rows,
            openCount: rows,
            tasks: (0..<rows).map { .init(id: UUID(), title: "Task \($0)", status: .todo) }
        )
    }

    @Test("write then read returns an equal snapshot")
    func writeReadRoundTrip() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = sampleSnapshot()
        try store.write(snap)
        #expect(store.read(filterID: snap.filterID) == snap)
    }

    @Test("read of an unknown filter returns nil")
    func readMissing() {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.read(filterID: UUID()) == nil)
    }

    @Test("index round-trips")
    func indexRoundTrip() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let index = WidgetSnapshotIndex(
            filters: [
                .init(id: UUID(), name: "Today", tintHex: nil),
                .init(id: UUID(), name: "Todayish", tintHex: "#8B45E8"),
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try store.writeIndex(index)
        #expect(store.readIndex() == index)
    }

    @Test("prune removes snapshots for filters not in the keep set")
    func prune() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keep = sampleSnapshot(filterID: UUID())
        let drop = sampleSnapshot(filterID: UUID())
        try store.write(keep)
        try store.write(drop)
        store.pruneFilters(keeping: [keep.filterID])
        #expect(store.read(filterID: keep.filterID) != nil)
        #expect(store.read(filterID: drop.filterID) == nil)
    }

    @Test("X11: clearAll removes the index and every per-filter snapshot")
    func clearAllRemovesEverything() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = sampleSnapshot()
        try store.write(snap)
        try store.writeIndex(WidgetSnapshotIndex(filters: [], generatedAt: Date()))

        store.clearAll()

        #expect(store.read(filterID: snap.filterID) == nil)
        #expect(store.readIndex() == nil)
    }

    @Test("X11: clearAll on an already-empty store is a harmless no-op")
    func clearAllOnEmptyStoreIsNoop() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        store.clearAll()

        #expect(store.readIndex() == nil)
    }

    @Test("X11: write still works after clearAll — the directory structure is recreated on demand")
    func writeAfterClearAllRecreatesDirectories() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let snap = sampleSnapshot()
        try store.write(snap)

        store.clearAll()
        try store.write(snap)

        #expect(store.read(filterID: snap.filterID) == snap)
    }

    // MARK: - LIL-95: legacy (pre-nesting) payload decode

    /// A pre-LIL-95 on-disk snapshot: `Row` had only `id`/`title`/`status`. A
    /// stale cache file from before this upgrade must decode cleanly rather
    /// than fail and force the widget through its cold-cache rebuild path.
    @Test("LIL-95: a legacy Row JSON missing parentID/depth/isContext decodes with safe defaults")
    func legacyRowPayloadDecodesWithDefaults() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filterID = UUID()
        let rowID = UUID()

        // Hand-authored legacy shape — no parentID/depth/isContext keys at all.
        let legacyJSON = """
        {
          "filterID": "\(filterID.uuidString)",
          "filterName": "Todayish",
          "tintHex": "#8B45E8",
          "generatedAt": "2023-11-14T22:13:20Z",
          "totalCount": 1,
          "openCount": 1,
          "tasks": [
            { "id": "\(rowID.uuidString)", "title": "Legacy task", "status": 0 }
          ]
        }
        """
        let filtersDir = dir.appendingPathComponent("filters", isDirectory: true)
        try FileManager.default.createDirectory(at: filtersDir, withIntermediateDirectories: true)
        try legacyJSON.data(using: .utf8)!.write(
            to: filtersDir.appendingPathComponent(filterID.uuidString).appendingPathExtension("json")
        )

        let decoded = try #require(store.read(filterID: filterID))
        #expect(decoded.tasks.count == 1)
        let row = decoded.tasks[0]
        #expect(row.id == rowID)
        #expect(row.title == "Legacy task")
        #expect(row.status == .todo)
        #expect(row.parentID == nil)
        #expect(row.depth == 0)
        #expect(row.isContext == false)
    }

    // MARK: - LIL-96: legacy (pre-status-counts) payload decode

    /// A pre-`LIL-96` on-disk snapshot has no `statusCounts` key at all. Every
    /// other field must still decode intact, and `statusCounts` must come back
    /// `nil` — not throw, which `WidgetSnapshotStore.read`'s `try?` would
    /// otherwise swallow into an indistinguishable-from-missing `nil` for the
    /// *whole snapshot*, forcing an unnecessary cold-cache rebuild.
    @Test("LIL-96: a legacy snapshot JSON missing statusCounts decodes with every other field intact")
    func legacySnapshotPayloadDecodesWithNilStatusCounts() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let filterID = UUID()
        let rowID = UUID()

        let legacyJSON = """
        {
          "filterID": "\(filterID.uuidString)",
          "filterName": "Todayish",
          "tintHex": "#8B45E8",
          "generatedAt": "2023-11-14T22:13:20Z",
          "totalCount": 1,
          "openCount": 1,
          "tasks": [
            { "id": "\(rowID.uuidString)", "title": "Legacy task", "status": 0 }
          ]
        }
        """
        let filtersDir = dir.appendingPathComponent("filters", isDirectory: true)
        try FileManager.default.createDirectory(at: filtersDir, withIntermediateDirectories: true)
        try legacyJSON.data(using: .utf8)!.write(
            to: filtersDir.appendingPathComponent(filterID.uuidString).appendingPathExtension("json")
        )

        let decoded = try #require(store.read(filterID: filterID))
        #expect(decoded.filterName == "Todayish")
        #expect(decoded.totalCount == 1)
        #expect(decoded.openCount == 1)
        #expect(decoded.statusCounts == nil)
        #expect(decoded.tasks.count == 1)
    }

    @Test("LIL-96: a snapshot with statusCounts round-trips it exactly")
    func statusCountsRoundTrips() throws {
        let (store, dir) = tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var snap = sampleSnapshot()
        snap.statusCounts = .init(todo: 2, started: 1, blocked: 0, closed: 3)
        try store.write(snap)

        let decoded = try #require(store.read(filterID: snap.filterID))
        #expect(decoded.statusCounts == snap.statusCounts)
    }
}
