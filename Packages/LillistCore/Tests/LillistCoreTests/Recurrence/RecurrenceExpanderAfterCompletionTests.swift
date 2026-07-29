import Testing
import Foundation
@testable import LillistCore

@Suite("RecurrenceExpander after-completion")
struct RecurrenceExpanderAfterCompletionTests {
    @Test("Returns completedAt + interval")
    func basic() {
        let completed = Date(timeIntervalSince1970: 1_800_000_000)
        let rule = RecurrenceRule.AfterCompletionRule(interval: 86_400 * 3)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next == completed.addingTimeInterval(86_400 * 3))
    }

    @Test("X16: a zero interval is clamped to the minimum, not permitted to return the same instant")
    func zeroInterval() {
        let completed = Date()
        let rule = RecurrenceRule.AfterCompletionRule(interval: 0)
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.minInterval)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next > completed)
    }

    @Test("X16: a negative interval is clamped to the minimum, not permitted to return an earlier date")
    func negativeIntervalClamped() {
        let completed = Date(timeIntervalSince1970: 1_000_000)
        let rule = RecurrenceRule.AfterCompletionRule(interval: -60)
        #expect(rule.interval == RecurrenceRule.AfterCompletionRule.minInterval)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next > completed)
    }
}
