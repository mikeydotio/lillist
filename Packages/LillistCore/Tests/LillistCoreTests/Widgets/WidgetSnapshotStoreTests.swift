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
}
