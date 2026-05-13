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

    @Test("Zero interval returns the same instant")
    func zeroInterval() {
        let completed = Date()
        let rule = RecurrenceRule.AfterCompletionRule(interval: 0)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next == completed)
    }

    @Test("Negative interval is permitted (returns earlier date) — caller's responsibility")
    func negativeIntervalAllowed() {
        let completed = Date(timeIntervalSince1970: 1_000_000)
        let rule = RecurrenceRule.AfterCompletionRule(interval: -60)
        let next = RecurrenceExpander.nextAfterCompletion(completedAt: completed, rule: rule)
        #expect(next < completed)
    }
}
