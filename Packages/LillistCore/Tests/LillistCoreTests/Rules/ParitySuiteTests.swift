import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Parity: NSPredicate vs SwiftEvaluator over the fixture set")
struct ParitySuiteTests {
    /// A named calendar context the parity run is executed under. Running the
    /// same fixtures under UTC and a DST-straddling America/New_York calendar
    /// catches day-window math that only breaks across a 23-hour day.
    struct CalendarContext: Sendable, CustomStringConvertible {
        let name: String
        let now: Date
        let calendar: Calendar
        var description: String { name }
    }

    static let contexts: [CalendarContext] = [
        CalendarContext(name: "UTC", now: ParityFixtures.now, calendar: ParityFixtures.calendar),
        CalendarContext(name: "America/New_York (DST)", now: ParityFixtures.nyNow, calendar: ParityFixtures.nyCalendar)
    ]

    /// The full fixture set: the hand-written behavioural fixtures plus the
    /// generated Field × Op × Value matrix.
    static let fixtures: [ParityFixture] = ParityFixtures.all + ParityMatrix.all

    @Test("Every fixture matches expected set in both evaluators, under each calendar",
          arguments: fixtures, contexts)
    func parity(_ fixture: ParityFixture, _ ctxInfo: CalendarContext) async throws {
        // --- NSPredicate path ---
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        try await ctx.perform {
            // First pass: seed every task (parents must exist for child wiring).
            var byID: [UUID: LillistTask] = [:]
            for seed in fixture.seeds {
                let t = LillistTask(context: ctx)
                t.id = seed.id
                t.title = seed.title
                t.notes = seed.notes
                t.status = seed.status
                // Date fields resolve calendar-relative offsets against THIS
                // run's calendar/now (offset wins over the fixed Date?), so a
                // window fixture keeps the same relative seed→window relationship
                // — and thus the same expected membership — under every calendar.
                t.start = seed.resolvedStart(now: ctxInfo.now, calendar: ctxInfo.calendar)
                t.deadline = seed.resolvedDeadline(now: ctxInfo.now, calendar: ctxInfo.calendar)
                t.createdAt = seed.createdAt
                t.modifiedAt = seed.modifiedAt
                t.closedAt = seed.resolvedClosedAt(now: ctxInfo.now, calendar: ctxInfo.calendar)
                t.deletedAt = seed.deletedAt
                t.isPinned = seed.isPinned
                byID[seed.id] = t
            }
            // Second pass: wire parent links.
            for seed in fixture.seeds {
                if let pid = seed.parentID, let p = byID[pid] {
                    byID[seed.id]?.parent = p
                }
            }
            // Tags
            var tagsByID: [UUID: LillistCore.Tag] = [:]
            for seed in fixture.seeds {
                for tid in seed.tagIDs {
                    if tagsByID[tid] == nil {
                        let tag = LillistCore.Tag(context: ctx)
                        tag.id = tid
                        tag.name = "tag-\(tid.uuidString.prefix(4))"
                        tag.tintColor = "#888888"
                        tagsByID[tid] = tag
                    }
                    if let t = byID[seed.id] {
                        t.addToTags(tagsByID[tid]!)
                    }
                }
            }
            // Journal note entries
            for seed in fixture.seeds {
                for body in seed.journalNoteBodies {
                    let j = JournalEntry(context: ctx)
                    j.id = UUID()
                    j.kind = .note
                    j.body = body
                    j.createdAt = Date()
                    j.task = byID[seed.id]
                }
            }
            // Attachments
            for seed in fixture.seeds {
                for kind in seed.attachmentKinds {
                    let a = Attachment(context: ctx)
                    a.id = UUID()
                    a.kind = kind
                    a.filename = "f"
                    a.uti = "public.data"
                    a.byteSize = 0
                    a.task = byID[seed.id]
                }
            }
            // Recurrence (a Series seed) and nudges (a NotificationSpec).
            for seed in fixture.seeds {
                guard let t = byID[seed.id] else { continue }
                if seed.isRecurring {
                    let series = Series(context: ctx)
                    series.id = UUID()
                    series.ruleJSON = nil
                    t.series = series
                }
                if seed.hasNudges {
                    let spec = NotificationSpec(context: ctx)
                    spec.id = UUID()
                    spec.kind = .defaultStart
                    spec.createdAt = Date()
                    spec.task = t
                }
            }
            try ctx.save()
        }

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                fixture.group,
                now: ctxInfo.now,
                calendar: ctxInfo.calendar
            )
            let tasks = try ctx.fetch(req)
            return Set(tasks.compactMap { $0.id })
        }

        // --- SwiftEvaluator path ---
        let swiftResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            let all = try ctx.fetch(req)
            var out: Set<UUID> = []
            for m in all {
                let snap = SwiftEvaluator.TaskSnapshot.from(managedObject: m)
                if SwiftEvaluator.evaluate(
                    group: fixture.group,
                    against: snap,
                    now: ctxInfo.now,
                    calendar: ctxInfo.calendar
                ) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        // --- Assertions ---
        #expect(nsResults == fixture.expected, "[\(ctxInfo)] [\(fixture.name)] NSPredicate path mismatch: got \(nsResults), expected \(fixture.expected)")
        #expect(swiftResults == fixture.expected, "[\(ctxInfo)] [\(fixture.name)] SwiftEvaluator path mismatch: got \(swiftResults), expected \(fixture.expected)")
        #expect(nsResults == swiftResults, "[\(ctxInfo)] [\(fixture.name)] paths diverged: NSPredicate=\(nsResults), Swift=\(swiftResults)")
    }
}
