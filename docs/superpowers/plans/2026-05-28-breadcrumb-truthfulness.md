# Breadcrumb Truthfulness Implementation Plan

> **📍 STATUS — ✅ MERGED to `main` (2026-06-04) — Wave 2.** All 7 tasks landed
> (commits `97ed3a8`..`7c2ebcd`); 705 LillistCore tests green ×3, warning-free.
> Nine `defer { Task { recordCrumb(success: true) } }` store sites converted to
> inline do/catch with a true success flag; `MigrationCoordinator.breadcrumb` is
> now `async` + awaited inline. Post-merge follow-up: replaced
> `MigrationRunnerExecutingTests.collectPhases`'s flaky 50ms-sleep drain with
> `await consumer.value` (the new `await` checkpoints exposed the latent race).
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **⚠️ Wave-1 reconciliation:**
> store-swap-safety has merged to main and reflowed `runMigration` in `MigrationCoordinator.swift`, so Task 6's line numbers are stale. Do NOT trust the literal line anchors (helper "69-74/71-74", calls "143/215/222"). The current state:
> - The `breadcrumb(_:success:)` helper is now at **lines 76-81** — its body still matches the plan's "before" snippet verbatim, so apply Step 1's `async` conversion as written.
> - The three call sites moved: **line 163** (`...start...`), **line 255** (`...completed...`), **line 262** (`...failed...`, `success: false`). Re-locate each by name and prepend `await` per the plan's own cross-plan note (Task 6 paragraph above Step 1). The call-site text is otherwise unchanged.
> store-swap-safety did NOT touch breadcrumb recording — the three sites are still detached-`Task` fire-and-forget — so Task 6 is still needed and conflicts with nothing already merged. Tasks 1-5 and Task 7 are clean (no Wave-1 overlap; all line numbers and method bodies verified against main).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every store mutator and the migration coordinator record a breadcrumb whose `success` flag reflects the *actual* outcome of the operation, recorded in operation order, so crash forensics are trustworthy.

**Architecture:** Nine store mutators currently use `defer { Task { [weak self] in await self?.recordCrumb(action, success: true) } }`, which (a) always claims `success: true` even when the wrapped `context.perform` throws, and (b) fires a *detached* `Task` whose completion races the method's return so crumbs land out of order. The fix replaces each `defer { Task { ... } }` with an inline `do { try await context.perform { ... }; await recordCrumb(action, success: true) } catch { await recordCrumb(action, success: false); throw error }` — exactly the shape `TaskStore.create`/`update`/`archive` already use. The migration coordinator's `breadcrumb(_:success:)` helper similarly spawns a detached `Task`; it becomes an `async` method that awaits the buffer inline so its start/completed/failed crumbs land in deterministic order. No public signatures change; the change is internal to each mutator body and to one private helper.

**Tech Stack:** Swift 6.2, Core Data (`NSManagedObjectContext.perform`), `BreadcrumbBuffer` actor, Swift Testing (`import Testing`, `@Test`/`#expect`), `TestStore.make()` in-memory persistence.

**Source findings:** conc-1, stores-2, persist-8.

---

## File Structure

### Modify

| Path | Responsibility | Lines touched (current) |
|------|----------------|--------------------------|
| `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` | Convert the 5 `defer` mutators (`hardDelete`, `reparent`, `transition`, `softDelete`, `restore`) to inline do/catch with true success flag. | 192–199, 220–241, 279–327, 386–397, 399–410 |
| `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift` | Convert the 2 `defer` mutators (`rename`, `delete`) to inline do/catch. | 80–90, 119–126 |
| `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift` | Convert `appendNote` `defer` to inline do/catch. | 33–47 |
| `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift` | Convert `insertAttachment` `defer` to inline do/catch (covers `addImage`/`addFile`/`addLinkPreview`, all of which route through it). | 204–237 |
| `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` | Make the `breadcrumb(_:success:)` helper `async` and `await` it at its three call sites so start/completed/failed crumbs land in operation order instead of via a detached `Task`. | 71–74, 143, 215, 222 |

### Modify (tests)

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` | Add failure-crumb tests for each of the nine converted mutators, asserting `success == false` when the operation throws, plus order-and-success tests for the happy paths that previously emitted via `defer`/detached `Task`. |

> **No `.xcdatamodel` edits** in this plan — the CompileCoreDataModel mtime touch ritual does not apply here.

> **Strengths to preserve:** the airtight DTO boundary (`record(from:)`) and the synchronous same-actor AsyncStream registration in the sync layer are untouched. Do **not** convert any `await recordCrumb(...)` back into a detached `Task` — that is the exact regression this plan removes.

---

### Task 1: Fix `JournalStore.appendNote` breadcrumb (warm-up — one mutator)

This is the smallest mutator and establishes the conversion pattern reused in every later task.

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` (add cases)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift` (lines 33–47)

- [ ] **Step 1: Write the failing test** — append these two `@Test` cases inside the `StoreBreadcrumbsTests` struct (after the existing `nilBuffer_isNoOp` test, before the closing `}`):

```swift
    @Test("JournalStore.appendNote records a journal.append success breadcrumb")
    func journalAppend_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let journals = JournalStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        journals.breadcrumbs = buffer
        let task = try await tasks.create(title: "T")
        _ = try await journals.appendNote(taskID: task, body: "note")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "journal.append" && $0.success }))
    }

    @Test("Failed JournalStore.appendNote records a journal.append failure breadcrumb")
    func journalAppend_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let journals = JournalStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        journals.breadcrumbs = buffer
        do {
            // No such task — fetchTask throws .notFound inside the perform.
            _ = try await journals.appendNote(taskID: UUID(), body: "orphan")
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "journal.append" && !$0.success }))
    }
```

- [ ] **Step 2: Run the test, expect failure** — the `_recordsFailure` case fails because the current `defer { Task { recordCrumb(success: true) } }` records `success: true` even though `appendNote` threw:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: `journalAppend_recordsFailure` fails with an expectation failure on `#expect(snap.contains(where: { $0.action == "journal.append" && !$0.success }))` (no failure crumb exists because the old code only ever records `success: true`).

- [ ] **Step 3: Implement the minimal change** — replace the whole `appendNote` method (current lines 33–47) with:

```swift
    @discardableResult
    public func appendNote(taskID: UUID, body: String) async throws -> UUID {
        do {
            let id: UUID = try await context.perform { [self] in
                let task = try fetchTask(id: taskID, in: context)
                let entry = JournalEntry(context: context)
                entry.id = UUID()
                entry.task = task
                entry.kind = .note
                entry.body = body
                entry.createdAt = Date()
                try context.save()
                return entry.id!
            }
            await recordCrumb("journal.append", success: true)
            return id
        } catch {
            await recordCrumb("journal.append", success: false)
            throw error
        }
    }
```

- [ ] **Step 4: Run the test, expect pass**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: all `StoreBreadcrumbsTests` cases pass, including `journalAppend_recordsSuccess` and `journalAppend_recordsFailure`. Output ends with `Test run with N tests passed`.

- [ ] **Step 5: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift && git commit -m "fix(crash): record true success flag for JournalStore.appendNote breadcrumb

The defer { Task { recordCrumb(success: true) } } pattern always claimed
success even when the wrapped perform threw, poisoning crash forensics.
Replace with inline do/catch recording the actual outcome in order.

Closes part of conc-1, stores-2, persist-8."
```

---

### Task 2: Fix `TagStore.rename` and `TagStore.delete` breadcrumbs

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` (add cases)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift` (lines 80–90 and 119–126)

- [ ] **Step 1: Write the failing test** — append these four `@Test` cases inside `StoreBreadcrumbsTests`:

```swift
    @Test("TagStore.rename records a tag.rename success breadcrumb")
    func tagRename_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(name: "Old")
        try await store.rename(id: id, to: "New")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.rename" && $0.success }))
    }

    @Test("Failed TagStore.rename records a tag.rename failure breadcrumb")
    func tagRename_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such tag — fetchManagedObject throws .notFound inside the perform.
            try await store.rename(id: UUID(), to: "Ghost")
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.rename" && !$0.success }))
    }

    @Test("TagStore.delete records a tag.delete success breadcrumb")
    func tagDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(name: "Doomed")
        try await store.delete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.delete" && $0.success }))
    }

    @Test("Failed TagStore.delete records a tag.delete failure breadcrumb")
    func tagDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TagStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.delete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.delete" && !$0.success }))
    }
```

- [ ] **Step 2: Run the test, expect failure**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: `tagRename_recordsFailure` and `tagDelete_recordsFailure` fail — the old `defer { Task { recordCrumb(success: true) } }` never emits a `success: false` crumb.

- [ ] **Step 3a: Implement `rename`** — replace the whole `rename` method (current lines 80–90) with:

```swift
    public func rename(id: UUID, to newName: String) async throws {
        do {
            try validateName(newName)
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                guard m.name != newName else { return }
                let resolved = try uniqueNameUnder(parent: m.parent, desired: newName, excluding: m)
                m.name = resolved
                try context.save()
            }
            await recordCrumb("tag.rename", success: true)
        } catch {
            await recordCrumb("tag.rename", success: false)
            throw error
        }
    }
```

- [ ] **Step 3b: Implement `delete`** — replace the whole `delete` method (current lines 119–126) with:

```swift
    public func delete(id: UUID) async throws {
        do {
            try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                context.delete(m)
                try context.save()
            }
            await recordCrumb("tag.delete", success: true)
        } catch {
            await recordCrumb("tag.delete", success: false)
            throw error
        }
    }
```

- [ ] **Step 4: Run the test, expect pass**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: all four new cases pass alongside the existing ones. Output ends with `Test run with N tests passed`.

- [ ] **Step 5: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift && git commit -m "fix(crash): record true success flag for TagStore rename/delete breadcrumbs

Replace defer { Task { recordCrumb(success: true) } } with inline do/catch
so a throwing rename/delete emits success:false. Also pulls validateName
inside the do so a rejected name is recorded as a failure crumb.

Closes part of conc-1, stores-2, persist-8."
```

---

### Task 3: Fix `AttachmentStore.insertAttachment` breadcrumb

`addImage`, `addFile`, and `addLinkPreview` all route through `insertAttachment`, so fixing it covers all three public mutators with a single conversion.

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` (add cases)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift` (lines 204–237)

- [ ] **Step 1: Write the failing test** — append these two `@Test` cases inside `StoreBreadcrumbsTests`. The tiny-PNG bytes mirror `AttachmentStoreTests.tinyPNG()`:

```swift
    @Test("AttachmentStore.addImage records an attachment.attach success breadcrumb")
    func attachmentAttach_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let tasks = TaskStore(persistence: persistence)
        let store = AttachmentStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let task = try await tasks.create(title: "T")
        let png = Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x63,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
        _ = try await store.addImage(taskID: task, filename: "snap.png", data: png)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "attachment.attach" && $0.success }))
    }

    @Test("Failed AttachmentStore.addImage records an attachment.attach failure breadcrumb")
    func attachmentAttach_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = AttachmentStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such task — fetchTask throws .notFound inside the perform.
            _ = try await store.addImage(taskID: UUID(), filename: "orphan.png", data: Data([0x00]))
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "attachment.attach" && !$0.success }))
    }
```

- [ ] **Step 2: Run the test, expect failure**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: `attachmentAttach_recordsFailure` fails — the old `defer { Task { recordCrumb(success: true) } }` never emits a `success: false` crumb.

- [ ] **Step 3: Implement the minimal change** — replace the whole `insertAttachment` method (current lines 204–237) with:

```swift
    private func insertAttachment(
        taskID: UUID,
        kind: AttachmentKind,
        filename: String,
        uti: String,
        data: Data?,
        linkPreviewJSON: String?
    ) async throws -> UUID {
        do {
            let id: UUID = try await context.perform { [self] in
                let task = try fetchTask(id: taskID, in: context)
                let journal = JournalEntry(context: context)
                journal.id = UUID()
                journal.task = task
                journal.kind = .attachment
                journal.createdAt = Date()
                journal.body = ""

                let att = Attachment(context: context)
                att.id = UUID()
                att.task = task
                att.journalEntry = journal
                att.kind = kind
                att.filename = filename
                att.uti = uti
                att.byteSize = Int64(data?.count ?? 0)
                att.data = data
                att.linkPreviewJSON = linkPreviewJSON
                att.createdAt = journal.createdAt

                try context.save()
                return att.id!
            }
            await recordCrumb("attachment.attach", success: true)
            return id
        } catch {
            await recordCrumb("attachment.attach", success: false)
            throw error
        }
    }
```

- [ ] **Step 4: Run the test, expect pass**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: both new cases pass. Output ends with `Test run with N tests passed`.

- [ ] **Step 5: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift && git commit -m "fix(crash): record true success flag for AttachmentStore.insertAttachment breadcrumb

Covers addImage/addFile/addLinkPreview which all route through this method.
Replace defer { Task { recordCrumb(success: true) } } with inline do/catch.

Closes part of conc-1, stores-2, persist-8."
```

---

### Task 4: Fix `TaskStore.hardDelete`, `softDelete`, and `restore` breadcrumbs

These three are the simplest `TaskStore` `defer` sites: `hardDelete` is a pure delete; `softDelete`/`restore` each do a `perform` then an optional `notificationScheduler.reconcile`. The success crumb must record after both the save and the reconcile succeed.

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` (add cases)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (lines 192–199, 386–397, 399–410)

- [ ] **Step 1: Write the failing test** — append these six `@Test` cases inside `StoreBreadcrumbsTests`:

```swift
    @Test("TaskStore.hardDelete records a task.purge success breadcrumb")
    func taskHardDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.hardDelete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.purge" && $0.success }))
    }

    @Test("Failed TaskStore.hardDelete records a task.purge failure breadcrumb")
    func taskHardDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.hardDelete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.purge" && !$0.success }))
    }

    @Test("TaskStore.softDelete records a task.delete success breadcrumb")
    func taskSoftDelete_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.delete" && $0.success }))
    }

    @Test("Failed TaskStore.softDelete records a task.delete failure breadcrumb")
    func taskSoftDelete_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.softDelete(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.delete" && !$0.success }))
    }

    @Test("TaskStore.restore records a task.restore success breadcrumb")
    func taskRestore_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.softDelete(id: id)
        try await store.restore(id: id)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.restore" && $0.success }))
    }

    @Test("Failed TaskStore.restore records a task.restore failure breadcrumb")
    func taskRestore_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.restore(id: UUID())
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.restore" && !$0.success }))
    }
```

- [ ] **Step 2: Run the test, expect failure**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: `taskHardDelete_recordsFailure`, `taskSoftDelete_recordsFailure`, and `taskRestore_recordsFailure` fail — the old `defer { Task { recordCrumb(success: true) } }` never emits `success: false`.

- [ ] **Step 3a: Implement `hardDelete`** — replace the whole method (current lines 192–199) with:

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

- [ ] **Step 3b: Implement `softDelete`** — replace the whole method (current lines 386–397) with:

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

- [ ] **Step 3c: Implement `restore`** — replace the whole method (current lines 399–410) with:

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

- [ ] **Step 4: Run the test, expect pass**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: all six new cases pass. Output ends with `Test run with N tests passed`.

- [ ] **Step 5: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift && git commit -m "fix(crash): record true success flag for TaskStore hardDelete/softDelete/restore

Replace defer { Task { recordCrumb(success: true) } } with inline do/catch.
softDelete/restore record success only after both the save and the optional
notification reconcile succeed.

Closes part of conc-1, stores-2, persist-8."
```

---

### Task 5: Fix `TaskStore.reparent` and `TaskStore.transition` breadcrumbs

These are the two remaining `TaskStore` `defer` sites. `reparent` can fail via `.notFound` or a cycle-validation `.validationFailed`; `transition` does a `perform` returning an optional spawned ID, then optional reconciles. Both must record the success crumb only after every step succeeds.

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift` (add cases)
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (lines 220–241, 279–327)

- [ ] **Step 1: Write the failing test** — append these four `@Test` cases inside `StoreBreadcrumbsTests`:

```swift
    @Test("TaskStore.reparent records a task.move success breadcrumb")
    func taskReparent_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let parent = try await store.create(title: "Parent")
        let child = try await store.create(title: "Child")
        try await store.reparent(id: child, newParent: parent)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.move" && $0.success }))
    }

    @Test("Failed TaskStore.reparent records a task.move failure breadcrumb")
    func taskReparent_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            // No such task — fetchManagedObject throws .notFound inside the perform.
            try await store.reparent(id: UUID(), newParent: nil)
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.move" && !$0.success }))
    }

    @Test("TaskStore.transition records a task.status.change success breadcrumb")
    func taskTransition_recordsSuccess() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        let id = try await store.create(title: "T")
        try await store.transition(id: id, to: .started)
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.status.change" && $0.success }))
    }

    @Test("Failed TaskStore.transition records a task.status.change failure breadcrumb")
    func taskTransition_recordsFailure() async throws {
        let persistence = try await TestStore.make()
        let store = TaskStore(persistence: persistence)
        let buffer = BreadcrumbBuffer()
        store.breadcrumbs = buffer
        do {
            try await store.transition(id: UUID(), to: .started)
            Issue.record("Expected notFound failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.status.change" && !$0.success }))
    }
```

- [ ] **Step 2: Run the test, expect failure**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: `taskReparent_recordsFailure` and `taskTransition_recordsFailure` fail — the old `defer { Task { recordCrumb(success: true) } }` never emits `success: false`.

- [ ] **Step 3a: Implement `reparent`** — replace the whole method (current lines 220–241) with:

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

- [ ] **Step 3b: Implement `transition`** — replace the whole method (current lines 279–327) with:

```swift
    public func transition(id: UUID, to newStatus: Status) async throws {
        do {
            let spawnedID: UUID? = try await context.perform { [self] in
                let m = try fetchManagedObject(id: id, in: context)
                let oldStatus = m.status
                guard oldStatus != newStatus else { return nil }
                m.status = newStatus
                m.modifiedAt = Date()
                if newStatus == .closed {
                    m.closedAt = m.modifiedAt
                } else if oldStatus == .closed {
                    m.closedAt = nil
                    // Reopening a previously archived task resurfaces it —
                    // a user explicitly un-completing is the signal that
                    // they want it back in the active view.
                    m.archivedAt = nil
                }

                // System journal entry for the transition.
                let entry = JournalEntry(context: context)
                entry.id = UUID()
                entry.task = m
                entry.kind = .statusChange
                entry.createdAt = m.modifiedAt
                entry.body = "\(oldStatus) → \(newStatus)"
                let payload: [String: Int] = ["from": oldStatus.rawValue, "to": newStatus.rawValue]
                entry.payload = try JSONSerialization.data(withJSONObject: payload)

                // Recurrence: spawn next instance ONLY on transition-to-closed.
                // Re-opening (oldStatus == .closed) does NOT undo the spawn,
                // per design Section 8.
                var spawnedID: UUID? = nil
                if newStatus == .closed {
                    spawnedID = RecurrenceSpawner.spawnIfNeeded(forClosedTask: m, in: context)
                }

                try context.save()
                return spawnedID
            }
            // Reconcile *after* the save so the persistent store reflects the
            // new state. The scheduler is property-injected; absent in tests
            // that don't care about notifications.
            if let scheduler = notificationScheduler {
                await scheduler.reconcile(taskID: id)
                if let spawnedID {
                    await scheduler.reconcile(taskID: spawnedID)
                }
            }
            await recordCrumb("task.status.change", success: true)
        } catch {
            await recordCrumb("task.status.change", success: false)
            throw error
        }
    }
```

- [ ] **Step 4: Run the test, expect pass**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter StoreBreadcrumbsTests
```

Expected: all four new cases pass. Output ends with `Test run with N tests passed`.

- [ ] **Step 5: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift && git commit -m "fix(crash): record true success flag for TaskStore reparent/transition breadcrumbs

Replace the last two defer { Task { recordCrumb(success: true) } } sites in
TaskStore. transition records success only after the save and any spawned-task
reconcile succeed; reparent records failure on .notFound or cycle validation.

Closes part of conc-1, stores-2, persist-8."
```

---

### Task 6: Make `MigrationCoordinator.breadcrumb` await inline (operation-order crumbs)

The coordinator's `breadcrumb(_:success:)` helper spawns a detached `Task` to record, so the start/completed/failed crumbs can land out of order relative to the migration phases. Make the helper `async` and `await` the buffer at each of its three call sites — the same operation-order principle applied to the stores. The three call sites are already inside `runMigration`, which is `async`, and all carry the correct `success` flag (start = true, completed = true, failed = false), so only the recording mechanism changes.

> **Cross-plan note:** `MigrationCoordinator.swift` is also touched by `store-swap-safety` [P0] (transactional reconfigure, lines ~127–138 and ~162–224) and `migration-adjacent-correctness` [P2] (reentrancy guard, `isStale`). Keep this edit surgical — only the `breadcrumb` helper (lines 71–74) and its three `breadcrumb(...)` call sites (lines 143, 215, 222). If `store-swap-safety` has already landed and reflowed `runMigration`, re-locate the three `breadcrumb(...)` calls by name and prepend `await`; the helper conversion is unchanged.

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (lines 71–74, 143, 215, 222)

- [ ] **Step 1: Convert the helper to async** — replace the `breadcrumb(_:success:)` helper (current lines 69–74):

```swift
    /// Fire-and-forget breadcrumb emit. Failures are silenced
    /// (breadcrumbs are diagnostic-only).
    private func breadcrumb(_ action: String, success: Bool = true) {
        guard let buffer = breadcrumbs else { return }
        Task { try? await buffer.record(action: action, success: success) }
    }
```

with:

```swift
    /// Breadcrumb emit, awaited inline so phase crumbs land in
    /// operation order (not via a detached Task that could reorder
    /// start/completed/failed). Failures are silenced — breadcrumbs
    /// are diagnostic-only.
    private func breadcrumb(_ action: String, success: Bool = true) async {
        guard let buffer = breadcrumbs else { return }
        try? await buffer.record(action: action, success: success)
    }
```

- [ ] **Step 2: Await at the start call site** — replace the line (current line 143):

```swift
        breadcrumb("sync mode change start \(op.rawValue)")
```

with:

```swift
        await breadcrumb("sync mode change start \(op.rawValue)")
```

- [ ] **Step 3: Await at the completed call site** — replace the line (current line 215):

```swift
            breadcrumb("sync mode change completed \(op.rawValue)")
```

with:

```swift
            await breadcrumb("sync mode change completed \(op.rawValue)")
```

- [ ] **Step 4: Await at the failed call site** — replace the line (current line 222):

```swift
            breadcrumb("sync mode change failed \(op.rawValue)", success: false)
```

with:

```swift
            await breadcrumb("sync mode change failed \(op.rawValue)", success: false)
```

- [ ] **Step 5: Build the package (no executing migration test under `swift test`)** — `MigrationCoordinatorTests` are gated by `.enabled(if: liveSwapAllowed)` and skip under `swift test` (no app bundle ID); executing coverage for them is owned by the `store-swap-safety` plan's `PersistenceReconfiguring` seam. Here, verify the change compiles under strict concurrency and the full suite is still green:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5 && swift test --package-path Packages/LillistCore 2>&1 | tail -15
```

Expected: build succeeds with **no warnings** (warnings-as-errors); the full test run ends with `Test run with N tests passed` and the `MigrationCoordinator` suite shows its cases skipped (not failed) under `swift test`.

- [ ] **Step 6: Commit**:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift && git commit -m "fix(sync): await migration breadcrumbs inline for operation order

The breadcrumb helper spawned a detached Task, so start/completed/failed
crumbs could land out of order relative to the migration phases. Make the
helper async and await it at all three call sites — the same operation-order
guarantee now applied to the stores.

Closes part of conc-1."
```

---

### Task 7: Full-suite regression sweep + breadcrumb-pattern audit

Confirm no `defer { Task { ... recordCrumb ... } }` remains anywhere in `LillistCore`, and the whole package is green with no warnings.

**Files:** none modified (verification only).

- [ ] **Step 1: Assert zero remaining detached-success breadcrumb sites** — this must print nothing:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "defer { Task" Packages/LillistCore/Sources/LillistCore/ ; echo "exit: $?"
```

Expected: no output lines (the `grep` finds nothing), `exit: 1`. If any line prints, a `defer { Task { ... } }` breadcrumb site survived — convert it using the do/catch pattern from Tasks 1–5 before proceeding.

- [ ] **Step 2: Assert every `recordCrumb` is awaited inline (no detached Task wrapping it)** — this must print nothing:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "Task {.*recordCrumb\|Task {.*buffer.record" Packages/LillistCore/Sources/LillistCore/ ; echo "exit: $?"
```

Expected: no output, `exit: 1`. (`MigrationCoordinator.breadcrumb` no longer wraps `buffer.record` in a `Task` after Task 6.)

- [ ] **Step 3: Run the entire LillistCore suite, warnings-as-errors**:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: ends with `Test run with N tests passed` (N ≥ the prior count + 20 new breadcrumb cases). No compiler warnings, no failures, no unexpected newly-failing suites.

- [ ] **Step 4: Confirm no behavioral regression in the touched stores' own suites** — run the store + crash suites explicitly:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "StoreBreadcrumbsTests|TaskStore|TagStore|JournalStore|AttachmentStore" 2>&1 | tail -20
```

Expected: all matched suites pass; `StoreBreadcrumbsTests` now reports the original 4 cases plus the 20 added across Tasks 1–5.

- [ ] **Step 5: No commit needed** — this task is verification only. If Steps 1–4 all pass, the plan is complete. If any step fails, return to the owning task (1–6) and fix before declaring done.

---

## Self-review checklist

- [ ] **conc-1** (breadcrumb false-success / detached-Task ordering across mutators *and* the migration coordinator) — closed by Tasks 1 (`journal.append`), 2 (`tag.rename`, `tag.delete`), 3 (`attachment.attach`), 4 (`task.purge`, `task.delete`, `task.restore`), 5 (`task.move`, `task.status.change`), and 6 (`MigrationCoordinator.breadcrumb` awaited inline). All nine `defer { Task { recordCrumb(success: true) } }` store sites are converted; the migration helper no longer spawns a detached `Task`. Task 7 Step 1/2 statically asserts none survive.
- [ ] **stores-2** (stores record false success on failed mutations) — closed by Tasks 1–5: each converted mutator now records `success: false` in its `catch` and `success: true` only after all steps (save + optional reconcile) succeed. Each has a forcing-failure test asserting `success == false` (`*_recordsFailure`).
- [ ] **persist-8** (persistence-layer breadcrumb false-success on delete/move/status/restore/rename) — closed by Tasks 2 (`rename`), 4 (`hardDelete`/`softDelete`/`restore`), and 5 (`reparent`/`transition`): delete, move, status-change, restore, and rename each emit a failure crumb on throw, asserted by their `*_recordsFailure` tests.
- [ ] Every code step shows the complete real method body matching current signatures (verified against the source at plan-authoring time).
- [ ] No `.xcdatamodel` edits — the CompileCoreDataModel mtime touch ritual is correctly omitted.
- [ ] Strengths preserved: DTO boundary untouched; no `await recordCrumb` reverted to a detached `Task`; synchronous AsyncStream registration in the sync layer untouched.
- [ ] Cross-plan collision on `MigrationCoordinator.swift` flagged (store-swap-safety, migration-adjacent-correctness) and the edit kept surgical to the `breadcrumb` helper + its 3 call sites.
