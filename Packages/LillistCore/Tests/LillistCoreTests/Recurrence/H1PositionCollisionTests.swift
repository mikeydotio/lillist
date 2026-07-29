import Testing
import Foundation
@testable import LillistCore

/// H1: `RecurrenceSpawner` used to anchor every spawn at
/// `series.seedTask.position + 0.5`. Since `series.seedTask` never changes
/// across a series' lifetime, every spawn after the first landed on the
/// exact same fractional position — a permanent sibling tie. The fix
/// computes placement live against the parent's current sibling set (the
/// same `nextPositionDetail`/`FractionalPosition` machinery `TaskStore
/// .create` uses), placing each spawn at the bottom.
@Suite("H1 — recurrence spawn position collision")
struct H1PositionCollisionTests {
    @Test("Two consecutive closes of a daily series produce three distinct positions")
    func consecutiveSpawnsDoNotCollide() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily standup")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        // Close #1: seed -> spawn #2.
        try await tasks.transition(id: seedID, to: .closed)
        let afterFirst = try await tasks.children(of: nil).filter { $0.title == "Daily standup" }
        #expect(afterFirst.count == 2)

        // Close #2: spawn #2 -> spawn #3. Pre-fix, spawn #3 lands at the
        // exact same position as spawn #2 (both anchored off the original
        // seed's stale position).
        let secondID = afterFirst.first { $0.status == .todo }!.id
        try await tasks.transition(id: secondID, to: .closed)
        let afterSecond = try await tasks.children(of: nil).filter { $0.title == "Daily standup" }
        #expect(afterSecond.count == 3)

        let positions = afterSecond.map(\.position)
        #expect(Set(positions).count == 3, "expected 3 distinct positions, got \(positions)")
    }

    @Test("A spawn lands at the bottom of the parent's current live sibling set")
    func spawnLandsAtCurrentBottom() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        // A manually created sibling, inserted after the series exists but
        // before the first close — proves the spawn is placed against the
        // LIVE sibling set at spawn time, not a value cached when the
        // series was created.
        _ = try await tasks.create(title: "Manually added", placement: .bottom)

        try await tasks.transition(id: seedID, to: .closed)

        let roots = try await tasks.children(of: nil)
        let manuallyAdded = roots.first { $0.title == "Manually added" }!
        let spawn = roots.first { $0.title == "Daily" && $0.id != seedID }!
        #expect(spawn.position > manuallyAdded.position, "spawn should land after the manually-added sibling, at the current bottom")
    }

    @Test("A spawn under a reparented seed resolves siblings against the seed's current parent")
    func spawnUsesSeedsCurrentParent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let folderID = try await tasks.create(title: "Folder")
        let seedID = try await tasks.create(title: "Daily")
        try await tasks.update(id: seedID) { $0.start = Date(timeIntervalSince1970: 1_800_000_000) }
        let rule = RecurrenceRule.calendar(.init(freq: .daily, interval: 1))
        _ = try await series.create(fromSeedTask: seedID, rule: rule)

        // Reparent the seed under "Folder" after the series exists.
        try await tasks.reparent(id: seedID, newParent: folderID)

        try await tasks.transition(id: seedID, to: .closed)

        let folderChildren = try await tasks.children(of: folderID)
        let spawn = folderChildren.first { $0.title == "Daily" && $0.id != seedID }
        #expect(spawn != nil, "spawn should be a sibling of the seed under its CURRENT parent")

        let roots = try await tasks.children(of: nil)
        #expect(roots.contains { $0.title == "Daily" } == false, "spawn must not land at the root — the seed was reparented")
    }
}
