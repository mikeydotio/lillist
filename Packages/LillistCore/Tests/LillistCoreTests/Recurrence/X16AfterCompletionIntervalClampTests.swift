import Testing
import Foundation
@testable import LillistCore

/// X16: `CalendarRule.interval` has a two-sided clamp (`RecurrenceRule
/// NormalizationTests`); `AfterCompletionRule.interval` was its unvalidated
/// sibling — a `0`/negative interval sets the spawned task's due date
/// at-or-before the completion instant, i.e. "permanently overdue on
/// creation." This suite mirrors `RecurrenceRuleNormalizationTests`' shape
/// for the `AfterCompletionRule` boundary.
@Suite("X16 — AfterCompletionRule interval clamp")
struct X16AfterCompletionIntervalClampTests {
    // MARK: - Memberwise init boundary

    @Test("init clamps a zero interval to the minimum")
    func initClampsZero() {
        let rule = RecurrenceRule.AfterCompletionRule(interval: 0)
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.minInterval)
    }

    @Test("init clamps a negative interval to the minimum")
    func initClampsNegative() {
        let rule = RecurrenceRule.AfterCompletionRule(interval: -60)
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.minInterval)
    }

    @Test("init preserves a valid positive interval")
    func initPreservesValid() {
        let rule = RecurrenceRule.AfterCompletionRule(interval: 86_400 * 3)
        #expect(rule.interval == 86_400 * 3)
    }

    @Test("init clamps an enormous interval down to the max")
    func initClampsHuge() {
        let rule = RecurrenceRule.AfterCompletionRule(interval: .greatestFiniteMagnitude)
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.maxInterval)
    }

    // MARK: - JSON decode boundary (CloudKit / Importer / CLI surface)

    private func afterCompletionJSON(interval: TimeInterval) -> Data {
        let json = """
        {"type":"afterCompletion","rule":{"interval":\(interval)}}
        """
        return Data(json.utf8)
    }

    @Test("decode clamps a negative interval to the minimum")
    func decodeClampsNegative() throws {
        let decoded = try JSONDecoder().decode(
            RecurrenceRule.self,
            from: afterCompletionJSON(interval: -100)
        )
        guard case .afterCompletion(let rule) = decoded else {
            Issue.record("expected .afterCompletion")
            return
        }
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.minInterval)
    }

    @Test("decode preserves a valid positive interval")
    func decodePreservesValid() throws {
        let decoded = try JSONDecoder().decode(
            RecurrenceRule.self,
            from: afterCompletionJSON(interval: 86_400 * 7)
        )
        guard case .afterCompletion(let rule) = decoded else {
            Issue.record("expected .afterCompletion")
            return
        }
        #expect(rule.interval == 86_400 * 7)
    }

    // MARK: - Point-of-use defense-in-depth (mirrors RecurrenceExpanderIntervalGuardTests)

    @Test("nextAfterCompletion re-clamps even when interval is forced out of range after construction")
    func expanderReClampsDefeatedBoundary() {
        var rule = RecurrenceRule.AfterCompletionRule(interval: 100)
        rule.interval = -50 // defeat the init-time clamp
        let completed = Date(timeIntervalSince1970: 1_000_000)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next > completed, "a defeated-boundary interval must still yield a date strictly after completion")
    }

    @Test("nextAfterCompletion stays finite for a defeated-boundary enormous interval")
    func expanderReClampsHugeDefeatedBoundary() {
        var rule = RecurrenceRule.AfterCompletionRule(interval: 100)
        rule.interval = .greatestFiniteMagnitude // defeat the init-time clamp
        let completed = Date(timeIntervalSince1970: 1_000_000)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next.timeIntervalSince1970.isFinite)
        #expect(next > completed)
    }

    // MARK: - End-to-end: the actual "permanently overdue" symptom

    @Test("A spawned after-completion instance's start is always strictly after closedAt, even from a defeated-boundary rule")
    func spawnedInstanceIsNeverOverdueOnCreation() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let series = SeriesStore(persistence: p)
        let id = try await tasks.create(title: "Water the plants")
        // Construct via decode to defeat the memberwise init's clamp, the
        // same untrusted-input path CloudKit/Importer/CLI use.
        let json = "{\"type\":\"afterCompletion\",\"rule\":{\"interval\":-3600}}"
        let rule = try JSONDecoder().decode(RecurrenceRule.self, from: Data(json.utf8))
        _ = try await series.create(fromSeedTask: id, rule: rule)

        try await tasks.transition(id: id, to: .closed)

        // LIL-84: compare against the seed task's own PERSISTED closedAt
        // (fetched back after the transition), not a `Date()` the test
        // captured independently beforehand. `spawn.start` is derived
        // directly from `closedAt` (`closedAt.addingTimeInterval(interval)`)
        // — comparing against the same value removes any dependency on how
        // much real wall-clock time elapsed between the test's own
        // `Date()` call and the moment `transition`'s `context.perform`
        // block actually ran, which is exactly the kind of scheduler-timing
        // gap that flaked this assertion under `swift test --parallel`
        // contention (the two values are now causally derived from each
        // other, not independently sampled).
        let seed = try await tasks.fetch(id: id)
        let closedAt = try #require(seed.closedAt)

        let roots = try await tasks.children(of: nil).filter { $0.title == "Water the plants" }
        let spawn = roots.first { $0.status == .todo }!
        #expect(spawn.start! > closedAt, "even a corrupt negative-interval rule must not spawn an already-overdue task")
    }
}
