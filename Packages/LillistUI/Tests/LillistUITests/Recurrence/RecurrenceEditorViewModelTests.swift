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
        let rule = vm.build()
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
        let rule = vm.build()
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
        let rule = vm.build()
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

    // MARK: - summary (structured; rendering lives in RecurrenceSummaryFormatter)

    @Test("summary: empty state is .never")
    func summary_never() {
        let vm = RecurrenceEditorViewModel(rule: nil)
        #expect(vm.summary == .never)
    }

    @Test("summary: daily/interval 1 is .calendar(.daily, 1)")
    func summary_everyDay() {
        let rule: RecurrenceRule = .calendar(.init(freq: .daily, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.daily, interval: 1))
    }

    @Test("summary: weekly/interval 1 is .calendar(.weekly, 1)")
    func summary_everyWeek() {
        let rule: RecurrenceRule = .calendar(.init(freq: .weekly, interval: 1))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.weekly, interval: 1))
    }

    @Test("summary: monthly/interval 3 is .calendar(.monthly, 3)")
    func summary_everyNMonths() {
        let rule: RecurrenceRule = .calendar(.init(freq: .monthly, interval: 3))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .calendar(.monthly, interval: 3))
    }

    @Test("summary: interval is clamped to >= 1 (defends against corrupt input)")
    func summary_clampsInterval() {
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        vm.freq = .daily
        vm.interval = 0
        #expect(vm.summary == .calendar(.daily, interval: 1))
    }

    @Test("summary: afterCompletion at 1 day is .afterCompletion(days: 1)")
    func summary_afterCompletion_singularDay() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .afterCompletion(days: 1))
    }

    @Test("summary: afterCompletion at 7 days is .afterCompletion(days: 7)")
    func summary_afterCompletion_pluralDays() {
        let rule: RecurrenceRule = .afterCompletion(.init(interval: 86_400 * 7))
        let vm = RecurrenceEditorViewModel(rule: rule)
        #expect(vm.summary == .afterCompletion(days: 7))
    }

    @Test("Default count is nil (unbounded); setting count=10 builds a bounded rule")
    func toggleRepeatForeverDefaultsCount() {
        // The Plan 22 "Repeat forever" toggle lives in the View; the View
        // model's `count` field is the underlying state. Contract: nil ==
        // unbounded, count > 0 == bounded. Toggling off the View toggle
        // assigns `count = 10` if previously nil; toggling on assigns nil.
        var vm = RecurrenceEditorViewModel(rule: nil)
        vm.repeats = true
        #expect(vm.count == nil, "Default is unbounded")
        vm.count = 10
        #expect(vm.count == 10)
        let rule = vm.build()
        if case .calendar(let c) = rule {
            #expect(c.count == 10)
        } else {
            Issue.record("Expected calendar rule")
        }
    }
}
