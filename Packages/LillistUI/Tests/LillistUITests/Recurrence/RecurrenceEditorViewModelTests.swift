import Testing
import Foundation
import LillistCore
@testable import LillistUI

@Suite("RecurrenceEditorViewModel")
struct RecurrenceEditorViewModelTests {
    @Test("Empty state produces no rule")
    func emptyState() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        #expect(vm.repeats == false)
        #expect(vm.build() == nil)
    }

    @Test("Daily/every 2 days round-trips")
    func dailyEveryTwo() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .daily
        vm.interval = 2
        let rule = try? #require(vm.build())
        if case .calendar(let calRule) = rule {
            #expect(calRule.freq == .daily)
            #expect(calRule.interval == 2)
        } else {
            Issue.record("Expected .calendar rule")
        }
    }

    @Test("Weekly with selected days")
    func weeklyWithByDay() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .weekly
        vm.byDay = [.monday, .wednesday, .friday]
        let rule = try? #require(vm.build())
        if case .calendar(let calRule) = rule {
            #expect(calRule.byDay == [.monday, .wednesday, .friday])
        } else {
            Issue.record("Expected .calendar rule")
        }
    }

    @Test("After-completion mode produces an after-completion rule")
    func afterCompletionMode() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.mode = .afterCompletion
        vm.afterCompletionSeconds = 86_400 // 1 day
        let rule = try? #require(vm.build())
        if case .afterCompletion(let after) = rule {
            #expect(after.interval == 86_400)
        } else {
            Issue.record("Expected .afterCompletion rule")
        }
    }

    @Test("Existing rule populates the view model")
    func roundTripFromExistingRule() {
        let original: RecurrenceRule = .calendar(.init(
            freq: .monthly,
            interval: 1,
            byMonthDay: [1, 15],
            count: 6
        ))
        let vm = RecurrenceEditorViewModel(rule: original)
        #expect(vm.repeats)
        #expect(vm.freq == .monthly)
        #expect(vm.byMonthDay == [1, 15])
        #expect(vm.count == 6)
    }
}
