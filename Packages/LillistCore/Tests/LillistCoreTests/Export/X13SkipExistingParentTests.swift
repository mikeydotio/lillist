import Testing
import Foundation
import CoreData
@testable import LillistCore

/// X13 — `.skipExisting` import still rewrote parents. The second pass that
/// wires `.parent` ran unconditionally over every DTO in the bundle, because
/// `taskByID`/`tagByID` are populated for skipped rows too. Two distinct
/// symptoms from one root cause, covered here for both tasks and tags per
/// the wave brief ("same question applies to tags' parents"):
///
/// 1. A row `.skipExisting` explicitly left alone still had its `.parent`
///    silently rewritten by the second pass.
/// 2. Parent resolution only ever consulted the bundle's own row set, never
///    the destination store — so a parent that legitimately exists in the
///    destination but isn't part of *this* bundle (a partial/targeted
///    import) was treated as "missing," silently promoting an otherwise-
///    correctly-inserted-or-updated child to root.
@Suite("X13 — .skipExisting import parent rewriting")
struct X13SkipExistingParentTests {
    // MARK: - Tasks

    @Test("skipExisting: a pre-existing task's parent is left untouched, even when the bundle assigns it one")
    func skippedTaskParentUntouched() async throws {
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        let localParentID = try await dstTasks.create(title: "Local parent")
        let existingChildID = try await dstTasks.create(title: "Local child (root)")

        // The bundle re-describes the SAME child id, now parented under a
        // DIFFERENT task that also exists in the bundle — under
        // .skipExisting this must have zero effect on the existing row.
        let bundleParentID = UUID()
        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tasks = [
            Self.task(bundleParentID, "Bundle parent", 0, parentID: nil),
            Self.task(existingChildID, "Local child (root)", 1, parentID: bundleParentID)
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksSkipped == 1)

        let parentID = try await Self.parentID(of: existingChildID, in: dst)
        #expect(parentID == nil, "skipped row's parent must not change")
        _ = localParentID
    }

    @Test("skipExisting: a NEW task whose parent already exists in the destination (but not in this bundle) is parented correctly, not promoted to root")
    func newTaskResolvesParentFromDestinationStore() async throws {
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        // The parent already exists locally; it is deliberately NOT part of
        // the incoming bundle (a partial/targeted import scenario).
        let existingParentID = try await dstTasks.create(title: "Existing parent")

        let newChildID = UUID()
        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tasks = [Self.task(newChildID, "New child", 0, parentID: existingParentID)]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksInserted == 1)

        let parentID = try await Self.parentID(of: newChildID, in: dst)
        #expect(parentID == existingParentID, "must fall back to the destination store, not silently root the child")
    }

    @Test("replaceExisting: an updated task's parent IS rewritten from the incoming DTO (intended replace semantics)")
    func replaceExistingStillRewritesParent() async throws {
        let dst = try await TestStore.make()
        let dstTasks = TaskStore(persistence: dst)
        let oldParentID = try await dstTasks.create(title: "Old parent")
        let newParentID = try await dstTasks.create(title: "New parent")
        let childID = try await dstTasks.create(title: "Child", parent: oldParentID)

        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tasks = [Self.task(childID, "Child", 0, parentID: newParentID)]
        let summary = try await importer.apply(document: doc, policy: .replaceExisting)
        #expect(summary.tasksUpdated == 1)

        let parentID = try await Self.parentID(of: childID, in: dst)
        #expect(parentID == newParentID)
    }

    @Test("A parent absent from both the bundle and the destination store still promotes the child to root")
    func trulyMissingParentStillRootsChild() async throws {
        let dst = try await TestStore.make()
        let childID = UUID()
        let danglingParentID = UUID() // nowhere: not in the bundle, not in the store
        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tasks = [Self.task(childID, "Orphaned child", 0, parentID: danglingParentID)]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksInserted == 1)

        let parentID = try await Self.parentID(of: childID, in: dst)
        #expect(parentID == nil)
    }

    // MARK: - Tags

    @Test("skipExisting: a pre-existing tag's parent is left untouched, even when the bundle assigns it one")
    func skippedTagParentUntouched() async throws {
        let dst = try await TestStore.make()
        let dstTags = TagStore(persistence: dst)
        let existingChildID = try await dstTags.create(name: "Local child", tintColor: nil)

        let bundleParentID = UUID()
        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tags = [
            Self.tag(bundleParentID, "Bundle parent", parentID: nil, position: 0),
            Self.tag(existingChildID, "Local child", parentID: bundleParentID, position: 1)
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tagsSkipped == 1)

        let parentID = try await Self.tagParentID(of: existingChildID, in: dst)
        #expect(parentID == nil, "skipped tag's parent must not change")
    }

    @Test("skipExisting: a NEW tag whose parent already exists in the destination (but not in this bundle) is parented correctly")
    func newTagResolvesParentFromDestinationStore() async throws {
        let dst = try await TestStore.make()
        let dstTags = TagStore(persistence: dst)
        let existingParentID = try await dstTags.create(name: "Existing parent", tintColor: nil)

        let newChildID = UUID()
        let importer = Importer(persistence: dst)
        var doc = Self.emptyDocument()
        doc.tags = [Self.tag(newChildID, "New child", parentID: existingParentID, position: 0)]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tagsInserted == 1)

        let parentID = try await Self.tagParentID(of: newChildID, in: dst)
        #expect(parentID == existingParentID)
    }

    // MARK: - Fixtures

    private static func emptyDocument() -> ExportSchema.Document {
        ExportSchema.Document(
            version: ExportSchema.version,
            exportedAt: Date(timeIntervalSince1970: 0),
            tasks: [],
            tags: [],
            journalEntries: [],
            attachments: [],
            preferences: ExportSchema.PreferencesDTO(
                defaultAllDayHour: 9, defaultAllDayMinute: 0,
                morningSummaryEnabled: false, morningSummaryHour: 8, morningSummaryMinute: 0,
                trashRetentionDays: 30, defaultTaskListSort: "manual"
            )
        )
    }

    private static func task(_ id: UUID, _ title: String, _ pos: Double, parentID: UUID?) -> ExportSchema.TaskDTO {
        ExportSchema.TaskDTO(
            id: id, title: title, notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: pos, isPinned: false, parentID: parentID, tagIDs: [],
            createdAt: Date(timeIntervalSince1970: pos), modifiedAt: nil,
            closedAt: nil, deletedAt: nil
        )
    }

    private static func tag(_ id: UUID, _ name: String, parentID: UUID?, position: Double) -> ExportSchema.TagDTO {
        ExportSchema.TagDTO(id: id, name: name, tintColor: nil, parentID: parentID, position: position)
    }

    private static func parentID(of id: UUID, in p: PersistenceController) async throws -> UUID? {
        let ctx = p.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            return try ctx.fetch(req).first?.parent?.id
        }
    }

    private static func tagParentID(of id: UUID, in p: PersistenceController) async throws -> UUID? {
        let ctx = p.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistCore.Tag>(entityName: "Tag")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            req.fetchLimit = 1
            return try ctx.fetch(req).first?.parent?.id
        }
    }
}
