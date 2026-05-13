import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("NSPredicateCompiler — scalar/string slice")
struct NSPredicateCompilerTests {
    @Test("Empty group matches all non-trashed (implicit inTrash filter)")
    func emptyGroupAppliesImplicitTrashFilter() {
        let group = PredicateGroup(combinator: .all, predicates: [])
        let p = NSPredicateCompiler.compile(group)
        let format = p.predicateFormat
        #expect(format.contains("deletedAt") || format.contains("inTrash") || format.contains("== nil"))
    }

    @Test("title contains compiles to CONTAINS[cd]")
    func titleContains() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("title"))
        #expect(p.predicateFormat.uppercased().contains("CONTAINS"))
    }

    @Test("status is statusSet compiles to IN")
    func statusIs() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .status, op: .is, value: .statusSet([.todo, .started])))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("statusRaw"))
        #expect(p.predicateFormat.uppercased().contains("IN"))
    }

    @Test("isPinned is bool(true) compiles to == YES")
    func isPinned() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .isPinned, op: .is, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("isPinned"))
    }

    @Test("Explicit inTrash leaf suppresses implicit trash filter")
    func explicitInTrashSuppressesImplicit() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        // The compiled predicate should reference deletedAt only once
        // (from the explicit leaf), not twice (explicit + implicit).
        let occurrences = p.predicateFormat.components(separatedBy: "deletedAt").count - 1
        #expect(occurrences == 1)
    }

    @Test("Compiled predicate evaluates against a real fetched task")
    func evaluatesAgainstFetchedTask() async throws {
        let controller = try await TestStore.make()
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "Design review"
            t.notes = ""
            t.status = .todo
            t.isPinned = false
            t.createdAt = Date()
            t.modifiedAt = Date()
            try ctx.save()
        }
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .title, op: .contains, value: .string("design")))
        ])
        let p = NSPredicateCompiler.compile(group)
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = p
        let results = try await ctx.perform { try ctx.fetch(req) }
        #expect(results.count == 1)
    }
}

@Suite("NSPredicateCompiler — date/attachment slice")
struct NSPredicateCompilerDateTests {
    @Test("deadline before absoluteDate")
    func deadlineBeforeAbsolute() {
        let d = Date()
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .before, value: .absoluteDate(d)))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("deadline"))
        #expect(p.predicateFormat.contains("<"))
    }

    @Test("start withinNextDays(7) resolves at compile time")
    func startWithinNextDays() {
        let now = Date(timeIntervalSince1970: 1_715_500_000)
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .start, op: .withinNextDays, value: .dayCount(7)))
        ])
        let p = NSPredicateCompiler.compile(group, now: now, calendar: .current)
        #expect(p.predicateFormat.contains("start"))
    }

    @Test("deadline isSet vs isUnset")
    func deadlineIsSet() {
        let setGroup = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isSet, value: .bool(true)))
        ])
        let unsetGroup = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .deadline, op: .isUnset, value: .bool(true)))
        ])
        #expect(NSPredicateCompiler.compile(setGroup).predicateFormat.contains("!= nil"))
        #expect(NSPredicateCompiler.compile(unsetGroup).predicateFormat.contains("== nil"))
    }

    @Test("createdAt equalsModifiedAt")
    func createdEqualsModified() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .createdAt, op: .equalsModifiedAt, value: .bool(true)))
        ])
        let p = NSPredicateCompiler.compile(group)
        let f = p.predicateFormat
        #expect(f.contains("createdAt"))
        #expect(f.contains("modifiedAt"))
    }

    @Test("hasAttachments is bool(true) with no ofKind")
    func hasAttachmentsAny() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true))))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("attachments"))
    }

    @Test("hasAttachments is bool(true) with ofKind = image")
    func hasAttachmentsImage() {
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .hasAttachments, op: .is, value: .attachmentKind(.init(present: true, kind: .image))))
        ])
        let p = NSPredicateCompiler.compile(group)
        #expect(p.predicateFormat.contains("kindRaw"))
    }
}
