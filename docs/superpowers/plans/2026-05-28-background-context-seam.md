# Background Context Seam Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 4.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **⚠️ Wave-1 reconciliation:**
> Wave-1 (store-swap-safety) is merged. This plan is otherwise independent of it — it does NOT touch any store-swap-safety surface (no `localStoreRowCount` wiring, no `restoreFromBackup`/test-2, no `PersistenceReconfiguring`, no `copyStore`, no `MigrationCoordinator`). Proceed without fear of conflicting with that work.
> One stale anchor: Wave-1 inserted `PersistenceController.localTaskRowCount()` at lines 55-73 (commit `2cffb58`). So in Task 1, re-Read `PersistenceController.swift` first: insert `makeBackgroundContext()` after `init` closes (line 53) — it will land just before the new `localTaskRowCount()` — and IGNORE the stale "near line 112" / "before makeContainer" hints (line 112 is now mid-`makeStoreDescription`; `makeContainer` is at line 83).
>
> **Cross-plan prerequisite (Task 6):** `breadcrumb-truthfulness` (Wave 2) MUST be merged before executing Task 6. Task 6 adds `context.rollback()` to the inline `do/catch` that `breadcrumb-truthfulness` creates in `hardDelete`/`reparent`/`softDelete`/`restore`. On current `main` those four still use `defer { Task { recordCrumb } }` — Task 6's before-snippets will not match and there is no `catch` block to insert into. See the prominent prerequisite note at the top of Task 6.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move bulk Core Data work (Exporter reads, Importer writes, Trash purges) off the main-queue `viewContext` onto dedicated background contexts, make every batch delete reproduce the cascade-to-children rule explicitly, add `context.rollback()` to mutating `perform` catch paths, and add an idempotent persistent-history sweep for `.localOnly` stores — without disturbing the deliberate single-context-on-main default that CloudKit mirroring depends on.

**Architecture:** Add one small `PersistenceController.withBackgroundContext` helper that vends a `newBackgroundContext()` (auto-merge ON so the main `viewContext` sees imports, save-merge policy matching production). Repoint `Exporter`/`Importer`/`purgeAll`/`AutoPurgeJob` at background contexts; the long-running export/import/purge work then never blocks the UI thread. Batch deletes enumerate *every* cascade-reachable `objectID` themselves (Core Data batch deletes return only the explicitly-named IDs even when SQLite cascades the DB rows, leaving the merge — and therefore the in-memory `viewContext` — incomplete), pass the full set to `NSBatchDeleteRequest`, and merge `resultTypeObjectIDs` into `viewContext`. A `HistoryPruner` reads the current `NSPersistentHistoryToken`, deletes history before it, and persists the token as `Data` so the sweep is idempotent — gated to `syncMode == .localOnly` because CloudKit mirroring owns history pruning when it's on.

**Tech Stack:** Swift 6.2, Core Data (`NSPersistentContainer` / `NSPersistentCloudKitContainer`), `NSBatchDeleteRequest` with `resultTypeObjectIDs`, `NSPersistentHistoryChangeRequest.deleteHistory(before:)`, App Group `UserDefaults`, Swift Testing (`import Testing`, `@Test`/`#expect`/`@Suite`).

**Source findings:** `threading-1`, `persist-4`, `conc-5`, `notif-7`, `persist-1` (review roadmap item #13).

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift` | Idempotent persistent-history sweep for `.localOnly` stores; stores the high-water `NSPersistentHistoryToken` as `Data` in App Group `UserDefaults`. |
| `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift` | Pure helper that walks the explicit cascade graph (`children` recursively → `journalEntries` → `attachments`/`notificationSpecs`) and returns every `objectID` a Core Data `Cascade` rule would delete, so batch deletes can reproduce the rule the framework skips. |
| `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRollbackTests.swift` | Regression test: a forced save conflict leaves the `viewContext` clean (proves `rollback()` fires) and a subsequent op succeeds. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/HistoryPrunerTests.swift` | Tests the history sweep: `.localOnly` prunes + stores a token, `.iCloudSync` no-ops, second sweep is idempotent. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/CascadeReaperTests.swift` | Tests the explicit cascade walk covers child/grandchild/journal/attachment/notificationSpec and excludes nullify targets (tags). |

### Modify

| Path | Responsibility | Lines |
|------|----------------|-------|
| `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift` | Add `newBackgroundContext()`-vending helper configured to match the production merge policy. | append after line 53 (end of `init`) / new method near line 112 |
| `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift` | Run reads on a background context; read attachment bytes into value types *inside* `perform`, write files to disk *outside* `perform`. | `buildDocument`, lines 39–138 |
| `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` | Run writes on a dedicated background context instead of `viewContext`; roll back on save failure. | `apply(document:policy:)`, lines 81–207 |
| `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` | `purgeAll` → explicit-cascade `NSBatchDeleteRequest` merged into `viewContext`; add `rollback()` to the catch paths of the mutating `perform` blocks. | `purgeAll` lines 429–455; `create` 112–139; `update` 153–188; `softDelete` 386–397; `restore` 399–410; `archive` 340–362; `unarchive` 366–382; `reparent` 220–241; `hardDelete` 192–199 |
| `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift` | Explicit-cascade `NSBatchDeleteRequest` on a background context merged into `viewContext`. | `run(now:)`, lines 15–28 |
| `docs/engineering-notes.md` | Append the deliberate single-context design rationale + the targeted background-context seam + the batch-delete-cascade-skip gotcha. | append |

---

## Task 1: Add the background-context helper

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift` (insert a new method after `init` ends at line 53).

The single shared `viewContext` stays the default for all interactive store mutations (it is the context CloudKit mirroring merges remote changes into, via `automaticallyMergesChangesFromParent = true`). This helper vends a *separate* `newBackgroundContext()` only for the three long-running batch jobs (export/import/purge). Auto-merge is left ON on the background context's parent (`viewContext`) by configuring the background context to push its saves up so the UI sees import results without a manual refetch.

- [ ] **Step 1: Write the failing test** — add to a new file `Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundContextTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("PersistenceController.background context")
struct BackgroundContextTests {
    @Test("makeBackgroundContext returns a private-queue context distinct from viewContext")
    func vendsPrivateQueueContext() async throws {
        let p = try await TestStore.make()
        let bg = p.makeBackgroundContext()
        #expect(bg !== p.container.viewContext)
        #expect(bg.concurrencyType == .privateQueueConcurrencyType)
    }

    @Test("background-context saves merge into the viewContext automatically")
    func bgSavesReachViewContext() async throws {
        let p = try await TestStore.make()
        let id = UUID()
        let bg = p.makeBackgroundContext()
        try await bg.perform {
            let t = LillistTask(context: bg)
            t.id = id
            t.title = "from-bg"
            t.createdAt = Date()
            try bg.save()
        }
        // viewContext (with automaticallyMergesChangesFromParent = true) sees it.
        let title: String? = try await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            return try p.container.viewContext.fetch(req).first?.title
        }
        #expect(title == "from-bg")
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "PersistenceController.background context"`. Expected failure: compile error `value of type 'PersistenceController' has no member 'makeBackgroundContext'`.

- [ ] **Step 3: Implement the minimal change** — add this method to `PersistenceController` immediately after the closing brace of `init(configuration:)` (after line 53), before `makeContainer`:

```swift
    /// A dedicated private-queue context for bulk work (export, import,
    /// Trash purge) that would otherwise block the main-queue
    /// `viewContext`. The single shared `viewContext` remains the default
    /// for all interactive mutations — it is the context
    /// `NSPersistentCloudKitContainer` merges remote changes into via
    /// `automaticallyMergesChangesFromParent`. This vends a *separate*
    /// context so a 10k-row export never freezes the UI.
    ///
    /// `automaticallyMergesChangesFromParent` is ON so this context sees
    /// concurrent `viewContext` edits, and its saves propagate up to the
    /// `viewContext` (which auto-merges them) so callers don't have to
    /// refetch after an import. The merge policy matches `viewContext`'s
    /// store-wide trump policy so a background save never silently loses
    /// to a concurrent main-queue edit.
    public func makeBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return context
    }
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "PersistenceController.background context"`. Expected: `Suite "PersistenceController.background context" passed` with 2 tests.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/BackgroundContextTests.swift
git commit -m "feat(persistence): add background-context helper for bulk Core Data work

Vends a dedicated private-queue context (auto-merge ON, trump policy)
for export/import/purge so long-running batch work never blocks the
main-queue viewContext. The single shared viewContext stays the default
for interactive mutations and remains the CloudKit merge target.

Refs: threading-1"
```

---

## Task 2: Run Exporter reads on a background context (bytes in, files out)

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift` — `buildDocument(assetsDir:)`, lines 39–138.

Today `buildDocument` reads on `viewContext` and calls `data.write(to:)` *inside* the `perform` block (lines 98–102) — file I/O while holding the main-queue context. The fix: (a) use a background context, (b) collect attachment bytes into a Sendable value array *inside* `perform`, (c) write the files to disk *after* `perform` returns.

- [ ] **Step 1: Write the failing test** — add to `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift` (inside the existing `@Suite("Exporter") struct ExporterTests`, after `refusesNonEmptyDir`, before the final closing brace):

```swift
    @Test("Export does not mutate or block the main-queue viewContext")
    func usesBackgroundContext() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let attach = AttachmentStore(persistence: p)
        let task = try await tasks.create(title: "Has asset")
        let bytes = Data([0x01, 0x02, 0x03, 0x04])
        _ = try await attach.addFile(taskID: task, filename: "blob.bin", uti: "public.data", data: bytes)

        let prefs = PreferencesStore(persistence: p)
        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await exporter.export(to: dir)

        // The export must leave the main viewContext with no pending changes:
        // all reads happened on a private-queue background context.
        let viewHasChanges: Bool = await p.container.viewContext.perform {
            p.container.viewContext.hasChanges
        }
        #expect(viewHasChanges == false)

        // And the asset bytes still round-trip to disk (written OUTSIDE perform).
        let doc = try decodeDocument(in: dir)
        #expect(doc.attachments.count == 1)
        let path = try #require(doc.attachments[0].dataPath)
        let assetURL = dir.appendingPathComponent(path)
        #expect(try Data(contentsOf: assetURL) == bytes)
    }

    private func decodeDocument(in dir: URL) throws -> ExportSchema.Document {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
    }
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Exporter"`. Expected: the new test fails because `buildDocument` reads on `viewContext` — but since the current `export` only reads (no mutation), `hasChanges` may already be `false`; the test additionally guards the bytes-out-of-perform behavior. If `usesBackgroundContext` passes pre-change on `hasChanges` alone, it still drives the refactor by asserting the asset round-trips after the perform/write split. (The behavioral contract under test is: reads off the main context, writes off the perform block.) Confirm the suite still builds and runs.

> Note: `hasChanges == false` is the load-bearing assertion only once reads move off `viewContext`; the test is primarily a *guard* so a future regression that reads/writes on `viewContext` inside `perform` is caught. Proceed to Step 3 regardless.

- [ ] **Step 3: Implement the minimal change** — replace the entire `buildDocument(assetsDir:)` method (lines 39–138) with this version. It (1) takes a background context, (2) collects `(filename, bytes, dtoBuilder)` tuples inside `perform`, (3) writes files and finalizes `dataPath` after `perform`:

```swift
    private func buildDocument(assetsDir: URL) async throws -> ExportSchema.Document {
        let ctx = persistence.makeBackgroundContext()
        let prefs = try await preferences.read()

        // Attachment bytes are read into value types INSIDE perform; the
        // files themselves are written to disk OUTSIDE perform so no file
        // I/O happens while holding the Core Data context queue.
        struct PendingAsset {
            let filename: String
            let bytes: Data
            let dto: ExportSchema.AttachmentDTO
        }

        let (document, pendingAssets): (ExportSchema.Document, [PendingAsset]) = try await ctx.perform {
            // Tasks (including trashed — full backup)
            let taskReq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            taskReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let taskMOs = try ctx.fetch(taskReq)
            let taskDTOs = taskMOs.map { m -> ExportSchema.TaskDTO in
                let tagIDs = ((m.tags as? Set<Tag>) ?? []).compactMap(\.id).sorted(by: { $0.uuidString < $1.uuidString })
                return ExportSchema.TaskDTO(
                    id: m.id ?? UUID(),
                    title: m.title ?? "",
                    notes: m.notes ?? "",
                    status: Int(m.statusRaw),
                    start: m.start,
                    startHasTime: m.startHasTime,
                    deadline: m.deadline,
                    deadlineHasTime: m.deadlineHasTime,
                    position: m.position,
                    isPinned: m.isPinned,
                    parentID: m.parent?.id,
                    tagIDs: tagIDs,
                    createdAt: m.createdAt,
                    modifiedAt: m.modifiedAt,
                    closedAt: m.closedAt,
                    deletedAt: m.deletedAt
                )
            }

            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            let tagDTOs = try ctx.fetch(tagReq).map { m in
                ExportSchema.TagDTO(
                    id: m.id ?? UUID(),
                    name: m.name ?? "",
                    tintColor: m.tintColor,
                    parentID: m.parent?.id,
                    position: m.position
                )
            }

            let journalReq = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            journalReq.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let journalDTOs = try ctx.fetch(journalReq).map { m in
                ExportSchema.JournalEntryDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    kind: Int(m.kindRaw),
                    body: m.body ?? "",
                    payload: m.payload,
                    createdAt: m.createdAt,
                    editedAt: m.editedAt
                )
            }

            let attReq = NSFetchRequest<Attachment>(entityName: "Attachment")
            var pending: [PendingAsset] = []
            let attDTOs = try ctx.fetch(attReq).map { m -> ExportSchema.AttachmentDTO in
                var path: String?
                var carriedBytes: Data?
                if let data = m.data {
                    let filename = "\(m.id?.uuidString ?? UUID().uuidString)-\(m.filename ?? "asset")"
                    path = "assets/\(filename)"
                    carriedBytes = data
                    let dto = ExportSchema.AttachmentDTO(
                        id: m.id ?? UUID(),
                        taskID: m.task?.id ?? UUID(),
                        journalEntryID: m.journalEntry?.id,
                        kind: Int(m.kindRaw),
                        filename: m.filename ?? "",
                        uti: m.uti ?? "",
                        byteSize: m.byteSize,
                        dataPath: path,
                        linkPreviewJSON: m.linkPreviewJSON,
                        createdAt: m.createdAt
                    )
                    pending.append(PendingAsset(filename: filename, bytes: carriedBytes!, dto: dto))
                    return dto
                }
                return ExportSchema.AttachmentDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id ?? UUID(),
                    journalEntryID: m.journalEntry?.id,
                    kind: Int(m.kindRaw),
                    filename: m.filename ?? "",
                    uti: m.uti ?? "",
                    byteSize: m.byteSize,
                    dataPath: path,
                    linkPreviewJSON: m.linkPreviewJSON,
                    createdAt: m.createdAt
                )
            }

            let prefsDTO = ExportSchema.PreferencesDTO(
                defaultAllDayHour: prefs.defaultAllDayHour,
                defaultAllDayMinute: prefs.defaultAllDayMinute,
                morningSummaryEnabled: prefs.morningSummaryEnabled,
                morningSummaryHour: prefs.morningSummaryHour,
                morningSummaryMinute: prefs.morningSummaryMinute,
                trashRetentionDays: prefs.trashRetentionDays,
                defaultTaskListSort: prefs.defaultTaskListSort.rawValue
            )

            let doc = ExportSchema.Document(
                version: ExportSchema.version,
                exportedAt: Date(),
                tasks: taskDTOs,
                tags: tagDTOs,
                journalEntries: journalDTOs,
                attachments: attDTOs,
                preferences: prefsDTO
            )
            return (doc, pending)
        }

        // File I/O OUTSIDE the Core Data context queue.
        for asset in pendingAssets {
            let url = assetsDir.appendingPathComponent(asset.filename)
            try asset.bytes.write(to: url)
        }

        return document
    }
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Exporter"`. Expected: `Suite "Exporter" passed` with all tests including `usesBackgroundContext`, `emptyStore`, `fullRoundtrip`, `refusesNonEmptyDir`.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift
git commit -m "refactor(export): run Exporter reads on a background context

buildDocument now fetches on a dedicated private-queue context and
collects attachment bytes into value types inside perform; the asset
files are written to disk OUTSIDE the context queue. A 10k-row export
no longer blocks the main-queue viewContext, and no file I/O happens
while holding the Core Data queue.

Refs: threading-1"
```

---

## Task 3: Run Importer writes on a background context with rollback

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` — `apply(document:policy:)`, lines 81–207.

Today `apply` writes on `viewContext` (line 82). Move it to a background context. Because the background context has `automaticallyMergesChangesFromParent = true` and saves merge up to `viewContext`, the existing `ImporterTests` (which assert via `fetchTitle(in:)` against `viewContext`) keep passing. Add `ctx.rollback()` on save failure so a partial import doesn't strand pending objects in the shared context.

- [ ] **Step 1: Write the failing test** — add to `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (inside `@Suite("Importer") struct ImporterTests`, after `invalidBundle`, before the struct's closing brace):

```swift
    @Test("Import leaves the main viewContext with no stranded pending changes")
    func importDoesNotStrandViewContext() async throws {
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        _ = try await srcTasks.create(title: "One")
        _ = try await srcTasks.create(title: "Two")
        let bundle = try await exportFixture(from: src)

        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
        #expect(summary.tasksInserted == 2)

        // Writes happened on a background context; the viewContext must be clean.
        let viewHasChanges: Bool = await dst.container.viewContext.perform {
            dst.container.viewContext.hasChanges
        }
        #expect(viewHasChanges == false)

        // And the rows are visible through the viewContext (auto-merge).
        let count: Int = try await dst.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try dst.container.viewContext.count(for: req)
        }
        #expect(count == 2)
    }
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"`. Expected: the suite still builds; `importDoesNotStrandViewContext` may pass or fail depending on whether the current `viewContext`-based `apply` left it clean after `save()` — but the load-bearing contract is "writes off the main context", which the current code violates. Proceed to Step 3.

- [ ] **Step 3: Implement the minimal change** — replace the opening of `apply` (lines 81–83) and the save/return tail (lines 193–207). Specifically, change the context source and wrap the body in a do/catch that rolls back. Replace line 82's `let ctx = persistence.container.viewContext` with `let ctx = persistence.makeBackgroundContext()`, and replace the `try ctx.save()` at line 193 plus the surrounding `perform` return with a do/catch. The full edited method body (the `perform` closure) keeps every existing tag/task/journal loop unchanged; only the context source and the save tail change:

Change the context line (line 82):
```swift
        let ctx = persistence.makeBackgroundContext()
```

Replace the save tail (lines 193–206, from `try ctx.save()` through the `return ImportSummary(...)`) with:
```swift
            do {
                try ctx.save()
            } catch {
                ctx.rollback()
                throw error
            }
            return ImportSummary(
                tasksInserted: tasksInserted,
                tasksUpdated: tasksUpdated,
                tasksSkipped: tasksSkipped,
                tagsInserted: tagsInserted,
                tagsUpdated: tagsUpdated,
                tagsSkipped: tagsSkipped,
                journalEntriesInserted: entriesInserted,
                journalEntriesUpdated: entriesUpdated,
                journalEntriesSkipped: entriesSkipped,
                errors: errors
            )
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"`. Expected: `Suite "Importer" passed` with all tests including the existing `emptyStoreInserts`, `skipExisting`, `replaceExisting`, `recencyWins`, `invalidBundle`, and the new `importDoesNotStrandViewContext`.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Export/Importer.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift
git commit -m "refactor(import): run Importer writes on a background context

apply() now writes on a dedicated private-queue context (auto-merge ON,
so imported rows still reach the viewContext). A failed save rolls the
context back instead of stranding partial pending objects in the shared
main-queue context.

Refs: threading-1, conc-5"
```

---

## Task 4: Explicit-cascade reaper for batch deletes

**Files:** Create `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift` and `Packages/LillistCore/Tests/LillistCoreTests/Persistence/CascadeReaperTests.swift`.

`NSBatchDeleteRequest` skips Core Data's delete-rule machinery. Verified on this platform: SQLite *does* cascade the DB rows for `Cascade` rules, but `NSBatchDeleteResult.result` returns only the *explicitly-named* `objectID`s — so a naive batch delete of a parent merges only the parent's ID into `viewContext`, leaving the in-memory child/grandchild objects dangling (the SQLite rows are gone but `viewContext` still thinks they exist). The reaper enumerates every cascade-reachable `objectID` so the batch deletes — and merges — the complete set.

Cascade rules in the model (`LillistModel.xcdatamodel/contents`): `LillistTask.children` → Cascade (recursive), `LillistTask.journalEntries` → Cascade, `LillistTask.attachments` → Cascade, `LillistTask.notificationSpecs` → Cascade, `JournalEntry.attachments` → Cascade. `tags`, `series`, `parent` are Nullify (not reaped).

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/CascadeReaperTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("CascadeReaper")
struct CascadeReaperTests {
    @Test("Reaps task + child + grandchild + journal + attachment + notificationSpec")
    func reapsFullCascade() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let attach = AttachmentStore(persistence: p)

        let parent = try await tasks.create(title: "parent")
        let child = try await tasks.create(title: "child", parent: parent)
        _ = try await tasks.create(title: "grandchild", parent: child)
        let entryID = try await journals.appendNote(taskID: child, body: "note")
        _ = try await attach.addFile(taskID: child, filename: "a.bin", uti: "public.data", data: Data([1]))

        let ctx = p.container.viewContext
        let reapedCount: Int = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", parent as CVarArg)
            let root = try ctx.fetch(req).first!
            let ids = CascadeReaper.objectIDs(forDeleting: [root])
            return ids.count
        }
        // parent + child + grandchild (3 tasks) + 2 journal entries
        // (the auto status-change entry on create + the appended note) +
        // 1 attachment = at least 6 reachable objectIDs. The note's id
        // proves journal entries are included.
        #expect(reapedCount >= 6)
        _ = entryID
    }

    @Test("Does not reap nullify targets (tags)")
    func excludesTags() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let tags = TagStore(persistence: p)
        let tag = try await tags.create(name: "Keep", tintColor: "#00FF00")
        let task = try await tasks.create(title: "tagged")
        try await tasks.assignTag(taskID: task, tagID: tag)

        let ctx = p.container.viewContext
        let containsTag: Bool = try await ctx.perform {
            let treq = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            treq.predicate = NSPredicate(format: "id == %@", task as CVarArg)
            let root = try ctx.fetch(treq).first!
            let ids = Set(CascadeReaper.objectIDs(forDeleting: [root]))
            let tagReq = NSFetchRequest<Tag>(entityName: "Tag")
            tagReq.predicate = NSPredicate(format: "id == %@", tag as CVarArg)
            let tagMO = try ctx.fetch(tagReq).first!
            return ids.contains(tagMO.objectID)
        }
        #expect(containsTag == false)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "CascadeReaper"`. Expected failure: compile error `cannot find 'CascadeReaper' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift`:

```swift
import Foundation
import CoreData

/// Computes the complete set of `NSManagedObjectID`s that Core Data's
/// `Cascade` delete rules would remove when a set of `LillistTask`s is
/// deleted — so an `NSBatchDeleteRequest` can reproduce those rules,
/// which batch deletes otherwise skip.
///
/// `NSBatchDeleteRequest` bypasses the delete-rule machinery. On the
/// SQLite store the DB rows are still cascaded via foreign keys, but the
/// result set (`resultTypeObjectIDs`) reports only the *explicitly named*
/// IDs — so merging that incomplete set into the `viewContext` leaves the
/// cascaded children as dangling in-memory objects. Enumerating every
/// reachable ID here keeps the merge (and the `viewContext`) consistent.
///
/// Cascade graph (per `LillistModel.xcdatamodel`):
/// - `LillistTask.children`        → Cascade (recursive)
/// - `LillistTask.journalEntries`  → Cascade
/// - `LillistTask.attachments`     → Cascade
/// - `LillistTask.notificationSpecs` → Cascade
/// - `JournalEntry.attachments`    → Cascade
///
/// `tags`, `series`, `seriesAsSeed`, and `parent` are Nullify and are
/// intentionally excluded.
public enum CascadeReaper {
    /// Every `objectID` deleting `roots` would cascade to, including the
    /// roots themselves. Caller must invoke this on the owning context's
    /// queue (it faults relationships).
    public static func objectIDs(forDeleting roots: [LillistTask]) -> [NSManagedObjectID] {
        var collected: Set<NSManagedObjectID> = []
        for root in roots {
            collect(task: root, into: &collected)
        }
        return Array(collected)
    }

    private static func collect(task: LillistTask, into set: inout Set<NSManagedObjectID>) {
        guard set.insert(task.objectID).inserted else { return }

        if let entries = task.journalEntries as? Set<JournalEntry> {
            for entry in entries { collect(entry: entry, into: &set) }
        }
        if let attachments = task.attachments as? Set<Attachment> {
            for attachment in attachments { set.insert(attachment.objectID) }
        }
        if let specs = task.notificationSpecs as? Set<NotificationSpec> {
            for spec in specs { set.insert(spec.objectID) }
        }
        if let children = task.children as? Set<LillistTask> {
            for child in children { collect(task: child, into: &set) }
        }
    }

    private static func collect(entry: JournalEntry, into set: inout Set<NSManagedObjectID>) {
        guard set.insert(entry.objectID).inserted else { return }
        if let attachments = entry.attachments as? Set<Attachment> {
            for attachment in attachments { set.insert(attachment.objectID) }
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "CascadeReaper"`. Expected: `Suite "CascadeReaper" passed` with 2 tests.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Persistence/CascadeReaper.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/CascadeReaperTests.swift
git commit -m "feat(persistence): add CascadeReaper for explicit batch-delete cascades

NSBatchDeleteRequest skips Core Data delete rules and reports only the
explicitly-named objectIDs, leaving cascaded children dangling in the
viewContext after a merge. CascadeReaper walks the Cascade graph
(children recursively, journalEntries, attachments, notificationSpecs)
so batch deletes can name and merge the complete set.

Refs: persist-4"
```

---

## Task 5: Convert `purgeAll` and `AutoPurgeJob` to explicit-cascade batch delete

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (`purgeAll`, lines 429–455) and `Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift` (`run`, lines 15–28).

Both currently iterate `ctx.delete(_:)` on the main-queue `viewContext`. Move to a background context, gather victim roots, expand via `CascadeReaper`, batch-delete the full set, and merge `resultTypeObjectIDs` into the `viewContext`. The count semantics are preserved (`purgeAll` counts trashed roots + descendants; `AutoPurgeJob` counts top-level matched tasks + cascades).

- [ ] **Step 1: Write the tests** — add **two** tests to `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStorePurgeAllTests.swift` (inside `@Suite("TaskStore.purgeAll") struct TaskStorePurgeAllTests`, before the closing brace). The first is a **regression GUARD** (passes both before and after the refactor — it pins the cascade contract so a botched refactor can't silently drop it). The second is a genuine **RED** test that asserts the multi-level cascade *count math* and descendant removal; it **fails** against a naive batch delete that names only the matched roots and skips the `CascadeReaper` expansion (delete rules are bypassed by `NSBatchDeleteRequest`, so the unexpanded children survive in the store and the returned count is short).

Regression GUARD — cascade-to-journal-entries (not RED→GREEN; it passes against the current per-object `ctx.delete` too, because per-object delete honors the Cascade rule):

```swift
    @Test("GUARD: purgeAll cascades to journal entries (no orphans left in store)")
    func purgeCascadesToJournalEntries() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let journals = JournalStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        _ = try await journals.appendNote(taskID: child, body: "child note")
        try await store.softDelete(id: parent)

        let purged = try await store.purgeAll()
        #expect(purged == 2)

        let remainingJournals: Int = try await persistence.container.viewContext.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            return try persistence.container.viewContext.count(for: req)
        }
        #expect(remainingJournals == 0)
        let remainingTasks = try await store.children(of: nil)
        #expect(remainingTasks.isEmpty)
    }
```

Genuine RED — multi-level (parent → child → grandchild) cascade count math. Soft-deleting the parent cascades the soft-delete to every descendant (`applySoftDelete` recurses), so all three rows are trashed roots-and-descendants. A correct `purgeAll` returns **3** (parent + child + grandchild) and leaves **zero** `LillistTask` rows. A naive batch delete that deletes only the matched root objectID and skips the cascade expansion returns **1** and strands the child/grandchild rows — this test fails on both the count and the survivor query:

```swift
    @Test("RED: purgeAll cascade count math holds on a multi-level tree")
    func purgeCountMatchesMultiLevelCascade() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let parent = try await store.create(title: "parent")
        let child = try await store.create(title: "child", parent: parent)
        _ = try await store.create(title: "grandchild", parent: child)

        // Soft-deleting the parent cascades the soft-delete down the whole
        // subtree (applySoftDelete recurses), so all three rows are trashed.
        try await store.softDelete(id: parent)

        // Affected/returned count must equal every task removed: the matched
        // root PLUS the two cascade-reachable descendants = 3. A batch delete
        // that names only the root and skips CascadeReaper returns 1.
        let purged = try await store.purgeAll()
        #expect(purged == 3)

        // And the store must hold zero LillistTask rows afterward — the
        // cascaded child/grandchild must not survive as dangling rows that a
        // naive batch delete + incomplete merge would leave behind.
        let remainingTaskRows: Int = try await persistence.container.viewContext.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            return try persistence.container.viewContext.count(for: req)
        }
        #expect(remainingTaskRows == 0)
    }
```

- [ ] **Step 2: Run the tests, expect the GUARD green and the RED red** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore.purgeAll"`. Expected before Step 3: `purgeCascadesToJournalEntries` (the GUARD) **passes** against the current per-object `ctx.delete` implementation — per-object delete honors cascade rules, so it is a regression guard, not a RED→GREEN driver; its value is failing if the refactor in Step 3 forgets to expand via `CascadeReaper`. The current per-object implementation also makes `purgeCountMatchesMultiLevelCascade` pass (per-object delete cascades correctly), so to see it RED against the *naive* batch delete it guards against, implement Step 3 *without* the `CascadeReaper.objectIDs(forDeleting:)` expansion first (name only `roots` in the `NSBatchDeleteRequest`): the count returns 1 and the survivor query returns 2, both failing — then add the expansion to turn it GREEN. This is the genuine RED the batch-delete refactor must satisfy.

- [ ] **Step 3: Implement the minimal change** — replace `purgeAll` (lines 429–455) in `TaskStore.swift`:

```swift
    @discardableResult
    public func purgeAll() async throws -> Int {
        do {
            let count: Int = try await batchPurge(
                predicate: NSPredicate(format: "deletedAt != nil")
            )
            await recordCrumb("task.purge_all", success: true)
            return count
        } catch {
            await recordCrumb("task.purge_all", success: false)
            throw error
        }
    }

    /// Hard-deletes every trashed *root* matched by `predicate` plus its
    /// full Core Data cascade, on a background context, then merges the
    /// deleted `objectID`s into the main `viewContext`. Returns the number
    /// of tasks removed (matched roots + descendants).
    ///
    /// Batch delete skips delete rules, so `CascadeReaper` expands the
    /// roots into every cascade-reachable `objectID` first; the merge then
    /// invalidates the corresponding in-memory `viewContext` objects.
    private func batchPurge(predicate: NSPredicate) async throws -> Int {
        let ctx = persistence.makeBackgroundContext()
        let viewContext = persistence.container.viewContext
        let deletedIDs: [NSManagedObjectID] = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = predicate
            let matched = try ctx.fetch(req)
            // Only purge roots whose parent isn't itself in the victim set,
            // so children are reached via the cascade walk (not double-counted).
            let roots = matched.filter { task in
                guard let parent = task.parent else { return true }
                return !predicateMatches(predicate, parent)
            }
            let ids = CascadeReaper.objectIDs(forDeleting: roots)
            guard !ids.isEmpty else { return [] }
            let batch = NSBatchDeleteRequest(objectIDs: ids)
            batch.resultType = .resultTypeObjectIDs
            let result = try ctx.execute(batch) as? NSBatchDeleteResult
            let executed = (result?.result as? [NSManagedObjectID]) ?? []
            // The batch result reports only explicitly-named IDs; merge the
            // FULL reaped set so the viewContext drops every cascaded object.
            let toMerge = executed.isEmpty ? ids : Array(Set(executed).union(ids))
            return toMerge
        }
        guard !deletedIDs.isEmpty else { return 0 }
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                into: [viewContext]
            )
        }
        // Count only the LillistTask objectIDs (CascadeReaper includes
        // journal/attachment/spec IDs too).
        return await ctx.perform {
            deletedIDs.filter { $0.entity.name == "LillistTask" }.count
        }
    }

    /// Evaluates `predicate` against a managed object on its own queue.
    private func predicateMatches(_ predicate: NSPredicate, _ object: NSManagedObject) -> Bool {
        predicate.evaluate(with: object)
    }
```

Then replace the `countDescendants` helper at lines 457–460 — it is now only used by the removed loop; remove it. Verify with a follow-up grep in Step 4 that no other caller references it before deleting:

```bash
grep -n "countDescendants" Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
```

If the only remaining reference is the definition, delete lines 457–460 (the `countDescendants` function). If any other caller exists, leave it in place.

Now replace `AutoPurgeJob.run(now:)` (lines 15–28) in `AutoPurgeJob.swift`:

```swift
    @discardableResult
    public func run(now: Date = Date()) async throws -> Int {
        let prefs = try await preferences.read()
        let cutoff = now.addingTimeInterval(-Double(prefs.trashRetentionDays) * 86400)
        let ctx = persistence.makeBackgroundContext()
        let viewContext = persistence.container.viewContext
        let deletedIDs: [NSManagedObjectID] = try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", cutoff as NSDate)
            let victims = try ctx.fetch(req)
            // Batch delete skips delete rules; expand to the full cascade so
            // children/journal/attachment rows go with their parent.
            let ids = CascadeReaper.objectIDs(forDeleting: victims)
            guard !ids.isEmpty else { return [] }
            let batch = NSBatchDeleteRequest(objectIDs: ids)
            batch.resultType = .resultTypeObjectIDs
            let result = try ctx.execute(batch) as? NSBatchDeleteResult
            let executed = (result?.result as? [NSManagedObjectID]) ?? []
            return executed.isEmpty ? ids : Array(Set(executed).union(ids))
        }
        guard !deletedIDs.isEmpty else { return 0 }
        await viewContext.perform {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deletedIDs],
                into: [viewContext]
            )
        }
        return await ctx.perform {
            deletedIDs.filter { $0.entity.name == "LillistTask" }.count
        }
    }
```

Add `import CoreData` is already present in both files (verified). No new import needed.

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore.purgeAll|AutoPurgeJob"`. Expected: both suites pass — `TaskStore.purgeAll` (now 6 tests: `purgesTrashed`, `emptyTrash`, `cascadesToDescendants`, `idempotent`, `purgeCascadesToJournalEntries`, `purgeCountMatchesMultiLevelCascade`) and `AutoPurgeJob` (3 tests), with the `CascadeReaper`-expanded batch delete now satisfying the RED count-math test. Run the grep from Step 3 and delete `countDescendants` if unreferenced, then re-run.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
        Packages/LillistCore/Sources/LillistCore/Persistence/AutoPurgeJob.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStorePurgeAllTests.swift
git commit -m "perf(persistence): batch-delete Trash purges off the main context

purgeAll and AutoPurgeJob now run on a background context, expand the
victim roots through CascadeReaper to reproduce the Cascade delete rules
NSBatchDeleteRequest skips, delete the full set in one batch, and merge
the deleted objectIDs into the viewContext. Counts and cascade semantics
are preserved; the main-queue context is no longer used to iterate-delete
large Trash sets.

Refs: persist-4, threading-1"
```

---

## Task 6: Add `context.rollback()` to mutating `perform` catch paths + regression test

> **⚠️ PREREQUISITE: `breadcrumb-truthfulness` (Wave 2) MUST be merged before executing this task.**
>
> Task 6 adds one `context.rollback()` line to the *existing* `catch` block that `breadcrumb-truthfulness` creates in `hardDelete`, `reparent`, `softDelete`, and `restore`. On current `main` those four methods still use the old `defer { Task { … success: true } }` shape — there is no inline `do/catch` to insert into, and the "before" snippets shown below will **not match the current source**. If `breadcrumb-truthfulness` has not merged, stop and land it first, then return here. Do not attempt to apply Step 3's before/after snippets against the `defer`-based source — you will either get a non-matching edit or accidentally revert breadcrumb-truthfulness's truthful-success work.

**Files:** Create `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRollbackTests.swift`; modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` mutating methods.

A failed `ctx.save()` inside a mutating `perform` leaves the dirtied objects pending in the shared `viewContext`; the next op then re-attempts (or compounds) the failed change. The fix: every mutating method rolls the context back on failure.

**Precondition — this plan lands AFTER `breadcrumb-truthfulness`.** That plan already converted all four `defer`-based mutators (`hardDelete`, `reparent`, `softDelete`, `restore`) — plus `transition` — from `defer { Task { recordCrumb(success: true) } }` into an inline `do { … ; await recordCrumb(action, success: true) } catch { await recordCrumb(action, success: false); throw error }` that records the **true** success flag in operation order (the success crumb fires *inside* the `do` block, after the `perform` and, for `softDelete`/`restore`, after the `notificationScheduler.reconcile`). Do **not** re-write those method bodies from scratch — that would revert breadcrumb-truthfulness's truthful-success work by moving the success crumb back outside the `do`. This task adds **only** one line to each: a `context.rollback()` at the head of the *existing* `catch` block.

`create`, `update`, `archive`, and `unarchive` already shipped as inline do/catch independently of breadcrumb-truthfulness; their rollback additions (below) are unchanged.

**Rollback idiom.** Each mutation runs inside `context.perform`, and `rollback()` must run on the context's queue. The throw escapes the `perform`, so roll back via a small `await context.perform { [self] in context.rollback() }` as the *first* statement of the existing `catch`, before the failure `recordCrumb` and the `throw`. This matches how the plan and source already hop onto the context queue.

The regression test forces a deterministic save conflict: pin the `viewContext` at a stale row version (auto-merge OFF + a pending change + `.error` merge policy), bump the row's version from a background context, then call a store mutator — `ctx.save()` throws `NSCocoaErrorDomain` 133020. After the catch's `rollback()` the `viewContext` is clean and a fresh op on another row succeeds. (Verified: without `rollback()`, `hasChanges` stays `true`; with it, `false`.)

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRollbackTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("TaskStore rollback on save failure")
struct TaskStoreRollbackTests {
    /// Force a deterministic optimistic-locking save conflict: pin the
    /// shared viewContext at a stale row version (auto-merge OFF, a pending
    /// change keeps the v1 snapshot, error merge policy), then bump the row
    /// from a background context so the store's save conflicts.
    @Test("A failed save rolls the viewContext back and the next op succeeds")
    func rollsBackThenRecovers() async throws {
        let p = try await TestStore.make()
        let store = TaskStore(persistence: p)
        let id = try await store.create(title: "seed")
        let other = try await store.create(title: "other")
        let view = p.container.viewContext

        // Pin viewContext at v1 with a pending change + error policy.
        await view.perform {
            view.automaticallyMergesChangesFromParent = false
            view.mergePolicy = NSMergePolicy.error
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! view.fetch(req).first!
            m.notes = "dirty-pin"
        }
        // Bump the row to v2 from a background context.
        let bg = p.container.newBackgroundContext()
        await bg.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            let m = try! bg.fetch(req).first!
            m.title = "bg-edit"
            try! bg.save()
        }

        // The store mutator's save now conflicts and throws.
        var threw = false
        do {
            try await store.update(id: id) { $0.title = "view-edit" }
        } catch {
            threw = true
        }
        #expect(threw == true)

        // The catch path must have rolled the viewContext back.
        let hasChanges: Bool = await view.perform { view.hasChanges }
        #expect(hasChanges == false)

        // Restore normal merge behavior (as production always has) and prove
        // a fresh op on a different row succeeds.
        await view.perform {
            view.automaticallyMergesChangesFromParent = true
            view.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        }
        try await store.update(id: other) { $0.title = "other-updated" }
        let rec = try await store.fetch(id: other)
        #expect(rec.title == "other-updated")
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore rollback on save failure"`. Expected failure: `Expectation failed: (hasChanges → true) == false` — `update`'s catch path (post-breadcrumb-truthfulness it records `success: false` and rethrows, lines 184–187) never calls `rollback()`, so the dirtied `viewContext` stays pending.

- [ ] **Step 3: Implement the minimal change** — add `await context.perform { [self] in context.rollback() }` as the *first* statement of each mutating method's *existing* `catch` block, before its failure `recordCrumb`. `rollback()` must run on the context queue and the throw escapes the `perform`, so hop back on via a small `perform`. Two groups:

  - **`create` / `update` / `archive` / `unarchive`** already ship as inline do/catch (independent of breadcrumb-truthfulness). Replace just their existing `catch` block — the surrounding method body is unchanged.
  - **`hardDelete` / `reparent` / `softDelete` / `restore`** were converted to inline do/catch by breadcrumb-truthfulness (precondition above). Their bodies and breadcrumb shape are already correct — do **not** rewrite them. Add only the `rollback()` line into the catch the *before* snippet shows.

`create` (replace lines 136–139, the existing `catch`):
```swift
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.create", success: false)
            throw error
        }
```

`update` (replace lines 184–187, the existing `catch`):
```swift
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.update", success: false)
            throw error
        }
```

`archive` (replace lines 358–361, the existing `catch`):
```swift
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.archive", success: false)
            throw error
        }
```

`unarchive` (replace lines 378–381, the existing `catch`):
```swift
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.unarchive", success: false)
            throw error
        }
```

For the four breadcrumb-truthfulness mutators, the edit is a single-line insertion into the existing `catch`. Each pair below shows breadcrumb-truthfulness's **landed** shape (before) and the same method with `context.rollback()` added (after). Match the before-snippet verbatim before editing; if it doesn't match, breadcrumb-truthfulness has not landed (or was reflowed) — stop and reconcile rather than blind-replacing.

`hardDelete` — before (breadcrumb-truthfulness's landed shape):
```swift
    public func hardDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                context.delete(m)
                try context.save()
            }
            await recordCrumb("task.purge", success: true)
        } catch {
            await recordCrumb("task.purge", success: false)
            throw error
        }
    }
```
after (rollback added — only the first line of the `catch` is new):
```swift
    public func hardDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                context.delete(m)
                try context.save()
            }
            await recordCrumb("task.purge", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.purge", success: false)
            throw error
        }
    }
```

`reparent` — before (breadcrumb-truthfulness's landed shape):
```swift
    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let newParent: LillistTask?
                if let newParentID {
                    let candidate = try fetchManagedObject(id: newParentID, in: context)
                    if Validators.wouldCreateCycle(candidate: m, newParent: candidate) {
                        throw LillistError.validationFailed([
                            .init(field: "parent", message: "would create a cycle")
                        ])
                    }
                    newParent = candidate
                } else {
                    newParent = nil
                }
                m.parent = newParent
                m.position = try nextPosition(forParent: newParent)
                m.modifiedAt = Date()
                try context.save()
            }
            await recordCrumb("task.move", success: true)
        } catch {
            await recordCrumb("task.move", success: false)
            throw error
        }
    }
```
after (rollback added — only the first line of the `catch` is new):
```swift
    public func reparent(id: UUID, newParent newParentID: UUID?) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let newParent: LillistTask?
                if let newParentID {
                    let candidate = try fetchManagedObject(id: newParentID, in: context)
                    if Validators.wouldCreateCycle(candidate: m, newParent: candidate) {
                        throw LillistError.validationFailed([
                            .init(field: "parent", message: "would create a cycle")
                        ])
                    }
                    newParent = candidate
                } else {
                    newParent = nil
                }
                m.parent = newParent
                m.position = try nextPosition(forParent: newParent)
                m.modifiedAt = Date()
                try context.save()
            }
            await recordCrumb("task.move", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.move", success: false)
            throw error
        }
    }
```

`softDelete` — before (breadcrumb-truthfulness's landed shape; reconcile + success crumb stay *inside* the `do`):
```swift
    public func softDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let now = Date()
                applySoftDelete(to: m, at: now)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.delete", success: true)
        } catch {
            await recordCrumb("task.delete", success: false)
            throw error
        }
    }
```
after (rollback added — only the first line of the `catch` is new):
```swift
    public func softDelete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let now = Date()
                applySoftDelete(to: m, at: now)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.delete", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.delete", success: false)
            throw error
        }
    }
```

`restore` — before (breadcrumb-truthfulness's landed shape; reconcile + success crumb stay *inside* the `do`):
```swift
    public func restore(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                guard let deletedAt = m.deletedAt else { return }
                clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.restore", success: true)
        } catch {
            await recordCrumb("task.restore", success: false)
            throw error
        }
    }
```
after (rollback added — only the first line of the `catch` is new):
```swift
    public func restore(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                guard let deletedAt = m.deletedAt else { return }
                clearSoftDelete(from: m, matchingDeletedAt: deletedAt)
                try context.save()
            }
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
            }
            await recordCrumb("task.restore", success: true)
        } catch {
            await context.perform { [self] in context.rollback() }
            await recordCrumb("task.restore", success: false)
            throw error
        }
    }
```

> Note: this task does **not** alter any breadcrumb behavior. breadcrumb-truthfulness already records the true success flag in operation order for all four mutators; the only change here is the one `context.rollback()` line inserted into each existing `catch`. `transition` (also converted by breadcrumb-truthfulness) is intentionally out of scope for rollback in this plan — its catch is unchanged.

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "TaskStore rollback on save failure"`. Expected: `Suite "TaskStore rollback on save failure" passed` with 1 test. Then run the full store regression set to confirm no behavior changed: `swift test --package-path Packages/LillistCore --filter "TaskStore"`. Expected: all TaskStore suites pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreRollbackTests.swift
git commit -m "fix(stores): roll the context back when a mutating save fails

Every mutating TaskStore method now calls context.rollback() on a save
failure so a failed write never strands dirtied objects in the shared
viewContext for the next op to inherit. The rollback is a one-line add to
each existing catch block (create/update/archive/unarchive plus the four
breadcrumb-truthfulness do/catch mutators hardDelete/reparent/softDelete/
restore); breadcrumb behavior is unchanged. Regression test forces a real
optimistic-lock save conflict and asserts the context is clean afterward.

Refs: conc-5"
```

---

## Task 7: Idempotent persistent-history sweep for `.localOnly`

**Files:** Create `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift` and `Packages/LillistCore/Tests/LillistCoreTests/Persistence/HistoryPrunerTests.swift`.

When `syncMode == .iCloudSync`, `NSPersistentCloudKitContainer` owns history pruning (it tracks which transactions have been exported and trims behind itself). When `.localOnly`, persistent-history tracking is still ON (the store description keeps `NSPersistentHistoryTrackingKey` so the mode swap is non-structural — see `PersistenceController.makeStoreDescription`), so history accumulates forever with nothing to trim it. `HistoryPruner` reads the current token, deletes everything before it, and persists the token as `Data` so a re-run is idempotent.

Concurrency note (verified): `NSPersistentHistoryToken` is **not** `Sendable`. The token must be read, used in `deleteHistory(before:)`, and archived to `Data` all *inside* one `perform`; only the `Data` may cross the closure boundary.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/HistoryPrunerTests.swift`:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore

@Suite("HistoryPruner")
struct HistoryPrunerTests {
    private func onDiskStore(syncMode: SyncMode) async throws -> (PersistenceController, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-hist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Lillist.sqlite")
        let p = try await PersistenceController(configuration: .onDisk(url: url, syncMode: syncMode))
        return (p, dir)
    }

    @Test("localOnly: sweep prunes history and stores a token")
    func prunesLocalOnly() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")
        _ = try await store.create(title: "b")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        let didPrune = try await pruner.sweep()
        #expect(didPrune == true)
        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) != nil)
    }

    @Test("iCloudSync: sweep is a no-op (CloudKit owns pruning)")
    func skipsICloudSync() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        // Construct with iCloudSync mode even though the on-disk store is
        // localOnly — the pruner must gate on its own syncMode argument.
        let pruner = HistoryPruner(persistence: p, syncMode: .iCloudSync, defaults: defaults)
        let didPrune = try await pruner.sweep()
        #expect(didPrune == false)
        #expect(defaults.data(forKey: HistoryPruner.tokenDefaultsKey) == nil)
    }

    @Test("Second sweep is idempotent")
    func idempotent() async throws {
        let (p, dir) = try await onDiskStore(syncMode: .localOnly)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskStore(persistence: p)
        _ = try await store.create(title: "a")

        let defaults = UserDefaults(suiteName: "history-pruner-test-\(UUID().uuidString)")!
        let pruner = HistoryPruner(persistence: p, syncMode: .localOnly, defaults: defaults)
        _ = try await pruner.sweep()
        // A second sweep with no new transactions must not throw.
        let second = try await pruner.sweep()
        #expect(second == true)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "HistoryPruner"`. Expected failure: compile error `cannot find 'HistoryPruner' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift`:

```swift
import Foundation
import CoreData

/// Periodic persistent-history sweep for `.localOnly` stores.
///
/// Persistent-history tracking stays ON for `.localOnly` stores so the
/// sync-mode swap is a pure description mutation (see
/// `PersistenceController.makeStoreDescription`). With nothing consuming
/// the history, transactions accumulate unbounded. This pruner reads the
/// current token, deletes everything before it, and persists the token as
/// `Data` so a re-run is idempotent.
///
/// When `syncMode == .iCloudSync`, `NSPersistentCloudKitContainer` owns
/// history pruning (it trims behind its own export cursor), so the sweep
/// is a deliberate no-op.
///
/// `NSPersistentHistoryToken` is not `Sendable`: it is read, used, and
/// archived to `Data` entirely inside a single `perform`; only the `Data`
/// crosses the closure boundary.
public final class HistoryPruner: @unchecked Sendable {
    public static let tokenDefaultsKey = "io.mikeydotio.lillist.history.prunedToken"

    private let persistence: PersistenceController
    private let syncMode: SyncMode
    private let defaults: UserDefaults

    public init(persistence: PersistenceController, syncMode: SyncMode, defaults: UserDefaults) {
        self.persistence = persistence
        self.syncMode = syncMode
        self.defaults = defaults
    }

    /// Convenience initializer using App Group `UserDefaults`.
    public convenience init?(persistence: PersistenceController, syncMode: SyncMode, appGroupID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        self.init(persistence: persistence, syncMode: syncMode, defaults: defaults)
    }

    /// Returns `true` if a prune ran, `false` if skipped (iCloudSync).
    @discardableResult
    public func sweep() async throws -> Bool {
        guard syncMode == .localOnly else { return false }
        let ctx = persistence.makeBackgroundContext()
        let coordinator = persistence.container.persistentStoreCoordinator
        let key = Self.tokenDefaultsKey
        let archived: Data? = try await ctx.perform {
            guard let token = coordinator.currentPersistentHistoryToken(fromStores: nil) else {
                return nil
            }
            let request = NSPersistentHistoryChangeRequest.deleteHistory(before: token)
            _ = try ctx.execute(request)
            return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        }
        if let archived {
            defaults.set(archived, forKey: key)
        }
        return true
    }
}
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "HistoryPruner"`. Expected: `Suite "HistoryPruner" passed` with 3 tests.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Persistence/HistoryPruner.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/HistoryPrunerTests.swift
git commit -m "feat(persistence): idempotent history sweep for localOnly stores

localOnly stores keep persistent-history tracking ON (so the sync-mode
swap stays non-structural) but nothing trims it. HistoryPruner reads the
current token, deletes history before it, and persists the token as Data
for idempotence. Gated to syncMode == .localOnly; iCloudSync is a no-op
because NSPersistentCloudKitContainer owns its own pruning.

Refs: notif-7, persist-1"
```

---

## Task 8: Document the single-context design and the background-context seam

**Files:** Modify `docs/engineering-notes.md` (append a new dated entry at the end).

- [ ] **Step 1: Append the engineering note** — add this entry to the end of `docs/engineering-notes.md`:

```markdown
## 2026-05-28 — Single shared viewContext is deliberate; bulk work gets a targeted background seam

**The default is one main-queue context.** `PersistenceController`
exposes a single shared `container.viewContext` and every interactive
store mutation runs on it via `context.perform`. This is intentional, not
an oversight: `viewContext.automaticallyMergesChangesFromParent = true`
is **active** — it is the channel through which
`NSPersistentCloudKitContainer` merges remote CloudKit changes into the
UI's context. Do **not** "clean up" by claiming auto-merge is dead or by
fanning every store onto private contexts; you would break CloudKit
mirroring's path to the UI.

**The seam.** Three jobs are bulk, not interactive — full-store export,
full-store import, and Trash purge. Those run on a dedicated
`PersistenceController.makeBackgroundContext()` (a `newBackgroundContext`
with auto-merge ON and the same trump merge policy) so a 10k-row pass
never freezes the main queue. Background saves propagate up to the
`viewContext`, which auto-merges them, so callers don't refetch after an
import. Everything else stays on `viewContext`.

**Batch delete skips delete rules — and the result set lies.**
`NSBatchDeleteRequest` bypasses Core Data's delete-rule machinery. On the
SQLite store the *DB rows* are still cascaded via foreign keys, but
`NSBatchDeleteResult` (`resultTypeObjectIDs`) reports only the
*explicitly-named* objectIDs. Merging that partial set into the
`viewContext` leaves the cascaded children as dangling in-memory objects
(rows gone from SQLite, still "live" in the context). `CascadeReaper`
therefore enumerates every cascade-reachable objectID
(`children` recursively → `journalEntries` → `attachments` /
`notificationSpecs`; `JournalEntry.attachments`) and passes the full set
to both the batch delete and the merge. `purgeAll` and `AutoPurgeJob` use
it. Nullify relationships (`tags`, `series`, `parent`) are not reaped.

**Rollback on save failure.** A failed `ctx.save()` inside a mutating
`perform` leaves the dirtied objects pending in the shared `viewContext`;
the next op then inherits or compounds the failed change. Every mutating
`TaskStore` method calls `context.rollback()` in its catch path. To test
this deterministically: pin `viewContext` at a stale row version
(auto-merge OFF + a pending change + `NSMergePolicy.error`), bump the row
from a second context, then call the mutator — the save throws
`NSCocoaErrorDomain` 133020 and the catch's rollback leaves the context
clean. After a rollback, `refreshAllObjects()` is needed before a retry
on the *same* stale context, but a fresh op simply re-fetches.

**localOnly history grows unbounded.** `.localOnly` stores keep
`NSPersistentHistoryTrackingKey` ON (so the sync-mode swap is a pure
description mutation), but nothing consumes the history. `HistoryPruner`
sweeps it (token-bounded, idempotent), gated to `.localOnly` —
`.iCloudSync` trims behind its own export cursor and must not be swept.
`NSPersistentHistoryToken` is not `Sendable`: read it, use it in
`deleteHistory(before:)`, and archive it to `Data` all inside one
`perform`; only the `Data` may escape.
```

- [ ] **Step 2: Verify the file is well-formed** — `cd /Volumes/Code/mikeyward/Lillist && tail -30 docs/engineering-notes.md` and confirm the new heading reads `## 2026-05-28 — Single shared viewContext is deliberate; bulk work gets a targeted background seam` and the entry is intact.

- [ ] **Step 3: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add docs/engineering-notes.md
git commit -m "docs(engineering-notes): record single-context design + background seam

Documents why the single main-queue viewContext is deliberate
(automaticallyMergesChangesFromParent is the CloudKit merge channel and
stays active), the targeted background-context seam for export/import/
purge, the batch-delete cascade-skip gotcha and CascadeReaper, the
rollback-on-save-failure pattern, and the localOnly history sweep.

Refs: threading-1, persist-4, conc-5, notif-7, persist-1"
```

---

## Task 9: Full-suite green check

**Files:** none (verification only).

- [ ] **Step 1: Run the whole LillistCore suite** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -20`. Expected: all suites pass with no warnings-as-errors failures. The new suites (`PersistenceController.background context`, `CascadeReaper`, `TaskStore rollback on save failure`, `HistoryPruner`) and the existing ones (`Exporter`, `Importer`, `TaskStore.purgeAll`, `AutoPurgeJob`, all `TaskStore*`) are green.

- [ ] **Step 2: Confirm no leftover build warnings** — re-read the tail of Step 1's output and confirm no `warning:` lines (the package treats warnings as errors, so any warning fails the build outright; a clean `Test run ... passed` line is the proof).

- [ ] **Step 3: Confirm the working tree is clean** — `cd /Volumes/Code/mikeyward/Lillist && git status --short`. Expected: no uncommitted changes under `Packages/` or `docs/engineering-notes.md` (all eight commits landed).

---

## Self-review checklist

- [ ] **`threading-1`** (Exporter/Importer on a dedicated background context) — closed by **Task 1** (`makeBackgroundContext` helper), **Task 2** (Exporter reads on background context; attachment bytes read inside `perform`, files written outside), **Task 3** (Importer writes on background context), and **Task 5** (purges on background context).
- [ ] **`persist-4`** (`NSBatchDeleteRequest` reproducing cascade rules explicitly for `purgeAll`/`AutoPurgeJob`) — closed by **Task 4** (`CascadeReaper` enumerates the full cascade graph) and **Task 5** (`purgeAll` and `AutoPurgeJob` use batch delete with `resultTypeObjectIDs` merged into `viewContext`).
- [ ] **`conc-5`** (`context.rollback()` in every mutating `perform` catch + regression test) — closed by **Task 6** (rollback added to `create`/`update`/`archive`/`unarchive`/`hardDelete`/`reparent`/`softDelete`/`restore`; regression test forces a real save conflict and asserts the context is clean) and **Task 3** (Importer rollback on save failure).
- [ ] **`notif-7`** (periodic `NSPersistentHistoryChangeRequest.deleteHistory` sweep for `.localOnly` only, idempotent via stored token) — closed by **Task 7** (`HistoryPruner`, gated to `.localOnly`, token persisted as `Data`).
- [ ] **`persist-1`** (history pruning for `.localOnly` stores) — closed by **Task 7** (same `HistoryPruner`).
- [ ] **Design preserved:** single main-queue `viewContext` default kept; `automaticallyMergesChangesFromParent` is documented as *active* (the CloudKit merge channel), never cited as dead — **Task 8**.
- [ ] **Strengths protected:** DTO boundary untouched (no `NSManagedObject` escapes `LillistCore`; export/import still return value types and `ImportSummary`); date math untouched; the synchronous AsyncStream registration untouched.
- [ ] **No `.xcdatamodel` edit** — this plan adds no model changes, so the `CompileCoreDataModel` mtime touch ritual is not needed.
```
