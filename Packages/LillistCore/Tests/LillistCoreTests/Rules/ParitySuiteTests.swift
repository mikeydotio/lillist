import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("Parity: NSPredicate vs SwiftEvaluator over the fixture set")
struct ParitySuiteTests {
    @Test("Every fixture matches expected set in both evaluators",
          arguments: ParityFixtures.all)
    func parity(_ fixture: ParityFixture) async throws {
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
                t.start = seed.start
                t.deadline = seed.deadline
                t.createdAt = seed.createdAt
                t.modifiedAt = seed.modifiedAt
                t.closedAt = seed.closedAt
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
            try ctx.save()
        }

        let nsResults: Set<UUID> = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                fixture.group,
                now: ParityFixtures.now,
                calendar: ParityFixtures.calendar
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
                    now: ParityFixtures.now,
                    calendar: ParityFixtures.calendar
                ) {
                    if let id = m.id { out.insert(id) }
                }
            }
            return out
        }

        // --- Assertions ---
        #expect(nsResults == fixture.expected, "[\(fixture.name)] NSPredicate path mismatch: got \(nsResults), expected \(fixture.expected)")
        #expect(swiftResults == fixture.expected, "[\(fixture.name)] SwiftEvaluator path mismatch: got \(swiftResults), expected \(fixture.expected)")
        #expect(nsResults == swiftResults, "[\(fixture.name)] paths diverged: NSPredicate=\(nsResults), Swift=\(swiftResults)")
    }
}
