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
