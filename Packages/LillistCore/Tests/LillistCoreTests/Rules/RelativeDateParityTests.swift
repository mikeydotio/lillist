import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Relative-date parity property test")
struct RelativeDateParityTests {
    /// Sweep N from 0 to 21. For each N, seed tasks with deadlines at every
    /// integer day offset from -10 to +30 and confirm both evaluators agree
    /// on which match `withinNextDays N`.
    @Test("withinNextDays(N) agrees across paths for N in 0...21",
          arguments: 0...21)
    func sweep(_ n: Int) async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext

        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar

        try await ctx.perform {
            for offset in -10...30 {
                let t = LillistTask(context: ctx)
                t.id = UUID()
                t.title = "off=\(offset)"
                t.notes = ""
                t.status = .todo
                t.deadline = cal.date(byAdding: .day, value: offset, to: now)!
                t.createdAt = now; t.modifiedAt = now
            }
            try ctx.save()
        }

        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .withinNextDays, value: .dayCount(n)))
        ])

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(group, now: now, calendar: cal)
            return Set(try ctx.fetch(req).compactMap { $0.id })
        }

        let swiftResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(req)
            var out: Set<UUID> = []
            for m in all {
                let snap = SwiftEvaluator.TaskSnapshot.from(managedObject: m)
                if SwiftEvaluator.evaluate(group: group, against: snap, now: now, calendar: cal) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        #expect(nsResults == swiftResults, "withinNextDays(\(n)) diverged: NS=\(nsResults.count), Swift=\(swiftResults.count)")
    }
}

@Suite("RelativeDate weeksFromNow overflow guard")
struct RelativeDateWeeksOverflowTests {
    /// `weeksFromNow(Int.max)` would trap on `n * 7`. The resolver must
    /// saturate the multiply and return a defined date (the start-of-today
    /// fallback when the day count overflows the calendar's range).
    @Test("weeksFromNow(Int.max) does not trap")
    func maxWeeksNoTrap() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        // Must not crash. Calendar.date(byAdding:) returns nil for an
        // out-of-range day count, so resolve falls back to start-of-today.
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(Int.max), now: now, calendar: cal)
        #expect(resolved == cal.startOfDay(for: now))
    }

    @Test("weeksFromNow(Int.min) does not trap")
    func minWeeksNoTrap() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        let startOfToday = cal.startOfDay(for: now)
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(Int.min), now: now, calendar: cal)
        // The clamp's job is "no arithmetic trap" — reaching this line at all
        // proves that. We additionally pin a directional property that holds
        // under Foundation's asymmetric out-of-range handling: a hugely
        // negative week offset can never move the date forward. Note the
        // asymmetry — Int.max days makes Calendar.date(byAdding:) return nil,
        // so resolve falls back to start-of-today; Int.min days makes Calendar
        // return a *defined* far-past Date (not nil), so the `?? startOfToday`
        // fallback never fires. Hence `<=` rather than `==`.
        #expect(resolved <= startOfToday)
    }

    @Test("weeksFromNow(2) still resolves to +14 days")
    func smallWeeksUnchanged() {
        let now = ParityFixtures.now
        let cal = ParityFixtures.calendar
        let resolved = RelativeDateResolver.resolve(.weeksFromNow(2), now: now, calendar: cal)
        let expected = cal.date(byAdding: .day, value: 14, to: cal.startOfDay(for: now))!
        #expect(resolved == expected)
    }
}
