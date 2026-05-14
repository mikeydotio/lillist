import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.FilterFlags")
struct FilterFlagsTests {
    @Test("Empty flags produce empty group with default combinator (all) when applyTrashImplicit=false")
    func emptyDefault() async throws {
        let p = try await TestStore.make()
        let flags = CLIBridge.FilterFlags()
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        #expect(group.combinator == .all)
        #expect(group.predicates.isEmpty)
    }

    @Test("Tag flag adds tag.includesAny leaf with resolved UUIDs")
    func tagFlag() async throws {
        let p = try await TestStore.make()
        let tagID = try await TagStore(persistence: p).create(name: "Work")
        var flags = CLIBridge.FilterFlags()
        flags.tags = ["Work"]
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        #expect(group.predicates.count == 1)
        if case .leaf(let leaf) = group.predicates[0] {
            #expect(leaf.field == .tag)
            #expect(leaf.op == .includesAny)
            if case .uuidSet(let ids) = leaf.value {
                #expect(ids == Set([tagID]))
            } else {
                Issue.record("expected uuidSet value")
            }
        } else {
            Issue.record("expected leaf")
        }
    }

    @Test("Status flag adds a single status.is leaf with statusSet")
    func multipleStatuses() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.statuses = [.todo, .started]
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        #expect(group.predicates.count == 1)
        if case .leaf(let leaf) = group.predicates[0] {
            #expect(leaf.field == .status)
            #expect(leaf.op == .is)
            if case .statusSet(let set) = leaf.value {
                #expect(set == Set([Status.todo, .started]))
            } else {
                Issue.record("expected statusSet")
            }
        } else {
            Issue.record("expected leaf for status")
        }
    }

    @Test("--any sets combinator to any")
    func anyCombinator() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.combinator = .any
        flags.tags = ["A", "B"]
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        #expect(group.combinator == .any)
    }

    @Test("--deadline-before parses the date and adds a leaf")
    func deadlineBefore() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.deadlineBefore = "+7d"
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        #expect(group.predicates.contains { p in
            if case .leaf(let leaf) = p { return leaf.field == .deadline && leaf.op == .before }
            return false
        })
    }

    @Test("--has-attachments adds hasAttachments leaf with present=true")
    func hasAttachments() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.hasAttachments = true
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        let leaf: Leaf? = group.predicates.compactMap { p -> Leaf? in
            if case .leaf(let l) = p, l.field == .hasAttachments { return l }
            return nil
        }.first
        #expect(leaf != nil)
        if let value = leaf?.value, case .attachmentKind(let m) = value {
            #expect(m.present == true)
        } else {
            Issue.record("expected attachmentKind value")
        }
    }

    @Test("Implicit inTrash=false predicate added by default")
    func implicitTrashFalse() async throws {
        let p = try await TestStore.make()
        let flags = CLIBridge.FilterFlags()
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: true)
        #expect(group.predicates.contains { p in
            if case .leaf(let leaf) = p { return leaf.field == .inTrash }
            return false
        })
    }

    @Test("--include-trash skips the implicit predicate")
    func includeTrashFlag() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.includeTrash = true
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: true)
        #expect(group.predicates.contains { p in
            if case .leaf(let leaf) = p { return leaf.field == .inTrash }
            return false
        } == false)
    }

    @Test("Unknown tag name yields an empty uuidSet rather than an error")
    func unknownTagSilent() async throws {
        let p = try await TestStore.make()
        var flags = CLIBridge.FilterFlags()
        flags.tags = ["Nonexistent"]
        let group = try await flags.toPredicateGroup(persistence: p, now: Date(), calendar: .current, applyTrashImplicit: false)
        if case .leaf(let leaf) = group.predicates[0],
           case .uuidSet(let ids) = leaf.value {
            #expect(ids.isEmpty)
        } else {
            Issue.record("expected leaf with uuidSet")
        }
    }
}
