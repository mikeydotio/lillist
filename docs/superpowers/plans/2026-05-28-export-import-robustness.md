# Export/Import Robustness Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 6.**
>
> **⚠️ Wave-4 reconciliation (2026-06-04):** the HARD DEPENDENCY this plan names (`background-context-seam`) **has landed** — `Importer.apply` and `Exporter.buildDocument` now run on `persistence.makeBackgroundContext()` (NOT `persistence.container.viewContext`), and `apply`'s `ctx.save()` already sits in a `do { try ctx.save() } catch { ctx.rollback(); throw }` block. **Re-Read `Importer.swift` and `Exporter.swift` before editing — anchor by structure.** Concrete deltas this plan must account for: (1) **Task 2 Step 3's "before" snippet is stale** — the opening line is now `let ctx = persistence.makeBackgroundContext()`, not `viewContext`; insert the version guard *above* that line and keep the existing rollback-on-save block intact (do NOT add a second rollback). (2) **Task 4's `applyEntry` rewrite still holds** — current main signature is `applyEntry(_ dto:, into row:, taskByID:)` with `row.task = taskByID[dto.taskID]`; the `owner: LillistTask` rewrite + orphan-skip loop are still needed. (3) **Test-file line anchors drifted:** Wave 4 appended `importDoesNotStrandViewContext` to `ImporterTests.swift` (closing `}` now ~179; `fetchTitle` helper now ~187–194) and `usesBackgroundContext` + a `decodeDocument` helper to `ExporterTests.swift` (closing `}` now ~128) — append new tests/helpers by structure (inside the struct / next to `fetchTitle`), ignore the absolute line numbers. **`ImporterTests.swift` already imports `CoreData`** (Task 3's CoreData-import edit applies only to `ExporterTests.swift`, which still lacks it). (4) **Reuse `Persistence/CascadeReaper.swift`** (`objectIDs(forDeleting:)` + per-entity `batchDelete(objectIDs:in:)`) for any batch-delete need rather than re-deriving a cascade walk. Tasks 1 and 3's `ExportSchema`/`LillistError` edits are untouched by Wave 4.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–5 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-5.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-6.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Importer`/`Exporter` robust to forward-incompatible schema versions, orphaned (nil-task) journal entries, and truncated JSON, with a documented all-or-nothing import transaction contract.

**Architecture:** Add a typed `LillistError.unsupportedExportVersion` and guard `document.version` at the top of `Importer.apply(document:policy:)` (accept equal, accept older as an upgrade, reject newer). Stop the `Exporter` from fabricating a random `UUID()` for journal entries (and attachments) whose owning task is nil by widening `JournalEntryDTO.taskID`/`AttachmentDTO.taskID` to optional; the `Importer` then skips journal rows whose `taskID` is nil or unresolved, recording them in `errors` and `journalEntriesSkipped`. The import stays a single fully-transactional `ctx.save()`; this contract is documented in the method's doc comment and proven by a mid-batch-failure test that asserts nothing persists when the save throws.

**Tech Stack:** Swift 6.2, Core Data (`NSPersistentCloudKitContainer`), Swift Testing (`import Testing`, `@Test`/`#expect`), `JSONDecoder`/`JSONEncoder` with `.iso8601`.

**Source findings:** import-1, import-2, import-3, export-1.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift` | Add `unsupportedExportVersion(found:supported:)` case + its `errorDescription`. |
| Modify | `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift` | Widen `JournalEntryDTO.taskID` and `AttachmentDTO.taskID` from `UUID` to `UUID?` so a nil owning-task survives the round trip honestly. |
| Modify | `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift` | Emit `m.task?.id` (nil-safe) for journal entries and attachments instead of `?? UUID()`. |
| Modify | `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` | Guard `document.version` before applying; skip nil/unresolved-task journal entries into `errors` + `journalEntriesSkipped`; document the all-or-nothing transaction contract. |
| Create/Modify | `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` | Add version-guard (newer/equal/down-level), orphan-entry, truncated-JSON, and mid-batch-failure tests. |
| Modify | `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift` | Add a test proving nil-task journal entries export as `taskID == nil`, not a fabricated UUID. |
| Modify | `Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift` | Cover the new error case in the localized-description sweep + an equality check. |

---

### Task 1: Add the `unsupportedExportVersion` error case (import-1, part 1)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift` (cases block lines 14-25; `errorDescription` switch lines 30-56)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift` (lines 38-56)

- [ ] **Step 1: Write the failing test** — Add the new case to the localized-description sweep and an equality assertion in `LillistErrorTests.swift`. Replace the existing `localizedDescriptions()` test (lines 38-56) and add an equality test after it:

```swift
    @Test("Error has localized description for every case")
    func localizedDescriptions() {
        let cases: [LillistError] = [
            .storeUnavailable(reason: "test"),
            .iCloudUnavailable(reason: "test"),
            .syncFailure(underlying: "test"),
            .validationFailed([]),
            .notFound,
            .ambiguous([]),
            .quotaExceeded(resource: "test"),
            .attachmentTooLarge(byteSize: 0),
            .attachmentFetchFailed(url: URL(string: "https://example.com")!),
            .migrationRequired,
            .migrationFailed(underlying: "test"),
            .modelUnavailable(searchedFilenames: ["LillistModel.momd"]),
            .unsupportedExportVersion(found: 2, supported: 1)
        ]
        for err in cases {
            #expect(err.localizedDescription.isEmpty == false)
        }
    }

    @Test("unsupportedExportVersion carries found and supported versions")
    func unsupportedExportVersion() {
        let err = LillistError.unsupportedExportVersion(found: 7, supported: 1)
        if case .unsupportedExportVersion(let found, let supported) = err {
            #expect(found == 7)
            #expect(supported == 1)
        } else {
            Issue.record("expected .unsupportedExportVersion")
        }
        #expect(err != LillistError.unsupportedExportVersion(found: 8, supported: 1))
    }
```

- [ ] **Step 2: Run the test, expect failure** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "LillistError"
  ```
  Expected: compile error `type 'LillistError' has no member 'unsupportedExportVersion'`.

- [ ] **Step 3: Implement the minimal change** — In `LillistError.swift`, add the case to the enum (after `.modelUnavailable` on line 25):

```swift
    case modelUnavailable(searchedFilenames: [String])
    case unsupportedExportVersion(found: Int, supported: Int)
```

  And add the matching arm to the `errorDescription` switch (after the `.modelUnavailable` arm on lines 54-55):

```swift
        case .modelUnavailable(let names):
            return "Lillist data model not found in app bundle (searched: \(names.joined(separator: ", ")))"
        case .unsupportedExportVersion(let found, let supported):
            return "This export was written by a newer version of Lillist (schema \(found); this app supports up to \(supported)). Update Lillist and try again."
```

- [ ] **Step 4: Run the test, expect pass** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "LillistError"
  ```
  Expected: `Suite "LillistError" passed`, all tests green (the two new assertions among them).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorTests.swift
  git commit -m "feat(export): add unsupportedExportVersion error case

Typed error for forward-incompatible export bundles. Closes part of import-1."
  ```

---

### Task 2: Guard `document.version` before applying (import-1, part 2)

> **`ExportSchema.version` baseline:** the version tests below are written relative to the current `ExportSchema.version` (today `1`, declared in `ExportSchema.swift`). They use `ExportSchema.version`, `… - 1`, and `… + 1` rather than literals so they stay correct as the schema climbs. If `version` is ever bumped, **no test logic changes** — only adjust the bare fixture integers (e.g. `versionOlderApplies`'s comment, or any hand-written literal) to track the new baseline. The down-level case (`version - 1`) assumes every field added since the prior version has a safe default at the DTO boundary, which is the contract the guard's doc comment states.

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` — the `apply(document:policy:)` declaration + its first statement (now `let ctx = persistence.makeBackgroundContext()` after Wave 4): insert the guard at the very top, *above* the `makeBackgroundContext()` line.
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (add three `@Test` methods)

- [ ] **Step 1: Write the failing test** — Append these three tests to `ImporterTests.swift` inside the `ImporterTests` struct, after the last `@Test` method (Wave 4 added `importDoesNotStrandViewContext` as the last test — append after it, before the struct's closing `}`, which is now ~line 179). They construct an `ExportSchema.Document` directly (the synthesized memberwise init is reachable via `@testable import LillistCore`):

```swift
    /// Build a minimal, valid-shaped Document at an arbitrary schema
    /// version with no rows, so version-guard behavior can be tested in
    /// isolation from row-merge logic.
    private func emptyDocument(version: Int) -> ExportSchema.Document {
        ExportSchema.Document(
            version: version,
            exportedAt: Date(timeIntervalSince1970: 0),
            tasks: [],
            tags: [],
            journalEntries: [],
            attachments: [],
            preferences: ExportSchema.PreferencesDTO(
                defaultAllDayHour: 9,
                defaultAllDayMinute: 0,
                morningSummaryEnabled: false,
                morningSummaryHour: 8,
                morningSummaryMinute: 0,
                trashRetentionDays: 30,
                defaultTaskListSort: "manual"
            )
        )
    }

    @Test("Document at the current schema version applies")
    func versionEqualApplies() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        let summary = try await importer.apply(
            document: emptyDocument(version: ExportSchema.version),
            policy: .skipExisting
        )
        #expect(summary.errors.isEmpty)
    }

    @Test("Document at an older schema version applies (forward upgrade)")
    func versionOlderApplies() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        // ExportSchema.version is 1 today; version 0 stands in for an
        // older bundle. If/when version climbs this stays a down-level case.
        let summary = try await importer.apply(
            document: emptyDocument(version: ExportSchema.version - 1),
            policy: .skipExisting
        )
        #expect(summary.errors.isEmpty)
    }

    @Test("Document at a newer schema version throws unsupportedExportVersion")
    func versionNewerThrows() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        do {
            _ = try await importer.apply(
                document: emptyDocument(version: ExportSchema.version + 1),
                policy: .skipExisting
            )
            Issue.record("expected unsupportedExportVersion to be thrown")
        } catch let error as LillistError {
            #expect(error == .unsupportedExportVersion(
                found: ExportSchema.version + 1,
                supported: ExportSchema.version
            ))
        }
    }
```

- [ ] **Step 2: Run the test, expect failure** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: `versionNewerThrows` fails with `Issue.record("expected unsupportedExportVersion to be thrown")` (today `apply` never inspects `version`, so the newer document is happily applied). `versionEqualApplies`/`versionOlderApplies` pass.

- [ ] **Step 3: Implement the minimal change** — In `Importer.swift`, insert the guard as the first statements of `apply(document:policy:)`. **Re-Read first — Wave 4 (`background-context-seam`) moved this onto a background context.** The current opening of `apply` is:

```swift
    public func apply(document: ExportSchema.Document, policy: ConflictPolicy) async throws -> ImportSummary {
        let ctx = persistence.makeBackgroundContext()
        return try await ctx.perform { [policy, self] in
```

  Replace the bare `public func apply(...) ... {` declaration line with the doc-commented declaration below, inserting the version guard *above* the existing `let ctx = persistence.makeBackgroundContext()` line (leave that line and the trailing `do { try ctx.save() } catch { ctx.rollback(); throw error }` block exactly as Wave 4 left them — do NOT revert to `viewContext`, do NOT add a second rollback):

```swift
    /// Apply a decoded export `document` to the store.
    ///
    /// ## Transaction contract (import-3)
    ///
    /// This is **all-or-nothing**: every row is staged in a single
    /// background-context `perform` block and committed by one
    /// `ctx.save()` at the end. If that save throws, the context is
    /// rolled back, the error propagates, and *nothing* is persisted
    /// — the returned `ImportSummary` (including its
    /// per-row `errors` array and the `*Skipped` counts) is **discarded
    /// along with the staged objects.** Callers must treat a thrown
    /// error as "the store is unchanged"; the `errors`/`*Skipped` detail
    /// is only meaningful on a successful return. Per-row recovery would
    /// require a per-row save/rollback model, which this manual-merge
    /// escape hatch deliberately does not adopt.
    public func apply(document: ExportSchema.Document, policy: ConflictPolicy) async throws -> ImportSummary {
        // Forward-incompatible bundles (written by a newer Lillist) are
        // rejected up front. Equal and older versions apply; older
        // bundles are read as-is since every field added since has a
        // safe default at the DTO boundary.
        guard document.version <= ExportSchema.version else {
            throw LillistError.unsupportedExportVersion(
                found: document.version,
                supported: ExportSchema.version
            )
        }
        let ctx = persistence.makeBackgroundContext()  // unchanged Wave-4 seam — do not revert to viewContext
        return try await ctx.perform { [policy, self] in
```

- [ ] **Step 4: Run the test, expect pass** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: `Suite "Importer" passed`; `versionEqualApplies`, `versionOlderApplies`, `versionNewerThrows` all green.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Export/Importer.swift Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift
  git commit -m "feat(import): reject forward-incompatible export bundles

Guard document.version before apply(): accept equal/older, throw
unsupportedExportVersion for newer. Documents the all-or-nothing
import transaction contract. Closes import-1; documents import-3."
  ```

---

### Task 3: Stop the Exporter fabricating UUIDs for nil-task rows (export-1)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift` (`JournalEntryDTO.taskID` ~46; `AttachmentDTO.taskID` ~56)
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift` (the `journalDTOs` map's `taskID:` line; the `attDTOs` map's `taskID:` line — **note: the attachment map now has TWO `taskID: m.task?.id ?? UUID()` sites**, one in the `if let data` branch and one in the fallback `return`; fix both. All these maps moved inside `buildDocument`'s background-context `perform` block in Wave 4 — re-anchor by the `?? UUID()` substring, not line number.)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift` (add one `@Test`)

- [ ] **Step 1: Write the failing test** — Append this test to `ExporterTests.swift` inside the `ExporterTests` struct, after the last `@Test` method (Wave 4 added `usesBackgroundContext` as the last test, followed by a private `decodeDocument` helper — append the new `@Test` after `usesBackgroundContext` and before the `decodeDocument` helper / struct close, now ~line 128). It creates a journal entry, then nulls its `task` relationship directly (simulating an orphan that synced/corruption can produce) and asserts the export carries `taskID == nil` rather than a fabricated UUID:

```swift
    @Test("A journal entry whose task is nil exports as taskID == nil, not a fabricated UUID")
    func nilTaskJournalEntryExportsNilTaskID() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let journals = JournalStore(persistence: p)
        let prefs = PreferencesStore(persistence: p)

        let task = try await tasks.create(title: "Soon to be orphaned")
        _ = try await journals.appendNote(taskID: task, body: "orphan me")

        // Sever the journal entry's task relationship in-place to model
        // a nil-task row (CloudKit can deliver dangling relationships).
        let ctx = p.container.viewContext
        try await ctx.perform {
            let req = NSFetchRequest<JournalEntry>(entityName: "JournalEntry")
            for entry in try ctx.fetch(req) {
                entry.task = nil
            }
            try ctx.save()
        }

        let exporter = Exporter(persistence: p, preferences: prefs)
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await exporter.export(to: dir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let doc = try decoder.decode(
            ExportSchema.Document.self,
            from: try Data(contentsOf: dir.appendingPathComponent("lillist.json"))
        )
        #expect(doc.journalEntries.count == 1)
        #expect(doc.journalEntries[0].taskID == nil)
    }
```

  This test also needs `CoreData` imported. The file currently imports only `Testing`, `Foundation`, and `@testable import LillistCore` (lines 1-3). Add the import — replace lines 1-3:

```swift
import Testing
import Foundation
@testable import LillistCore
```

  with:

```swift
import Testing
import Foundation
import CoreData
@testable import LillistCore
```

- [ ] **Step 2: Run the test, expect failure** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Exporter"
  ```
  Expected: compile error `value of optional type 'UUID?' ... ` is NOT the failure — instead the test compiles (today `taskID` is non-optional `UUID`) and fails at runtime on `#expect(doc.journalEntries[0].taskID == nil)` because the Exporter writes `m.task?.id ?? UUID()` (a fabricated UUID), so `taskID` is non-nil. Actual failure: `Expectation failed: doc.journalEntries[0].taskID == nil`.

- [ ] **Step 3: Implement the minimal change** — Two edits.

  (a) In `ExportSchema.swift`, widen the two `taskID` fields. Change `JournalEntryDTO.taskID` (~46):

```swift
    public struct JournalEntryDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID?
        public var kind: Int
        public var body: String
        public var payload: Data?
        public var createdAt: Date?
        public var editedAt: Date?
    }
```

  Change `AttachmentDTO.taskID` (~56):

```swift
    public struct AttachmentDTO: Codable, Sendable {
        public var id: UUID
        public var taskID: UUID?
        public var journalEntryID: UUID?
        public var kind: Int
        public var filename: String
        public var uti: String
        public var byteSize: Int64
        /// Relative path under the export's `assets/` folder. Nil for link previews.
        public var dataPath: String?
        public var linkPreviewJSON: String?
        public var createdAt: Date?
    }
```

  (b) In `Exporter.swift`, stop fabricating. Change the journal map (the `journalDTOs` map) from `taskID: m.task?.id ?? UUID(),` to `taskID: m.task?.id,`:

```swift
            let journalDTOs = try ctx.fetch(journalReq).map { m in
                ExportSchema.JournalEntryDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id,
                    kind: Int(m.kindRaw),
                    body: m.body ?? "",
                    payload: m.payload,
                    createdAt: m.createdAt,
                    editedAt: m.editedAt
                )
            }
```

  And the attachment map (the `attDTOs` map) from `taskID: m.task?.id ?? UUID(),` to `taskID: m.task?.id,` — **both occurrences**. Wave 4 split this map into two `AttachmentDTO` constructions: one in the `if let data = m.data { … }` branch (the `dto` appended to `pending`) and one in the fallback `return` for attachments with no bytes. Each has its own `taskID:` line; fix both. The fallback `return` looks like:

```swift
                return ExportSchema.AttachmentDTO(
                    id: m.id ?? UUID(),
                    taskID: m.task?.id,
                    journalEntryID: m.journalEntry?.id,
                    kind: Int(m.kindRaw),
                    filename: m.filename ?? "",
                    uti: m.uti ?? "",
                    byteSize: m.byteSize,
                    dataPath: path,
                    linkPreviewJSON: m.linkPreviewJSON,
                    createdAt: m.createdAt
                )
```

  and the in-branch `dto` (appended to `pending`) carries the same `taskID:` line — apply the identical edit there.

- [ ] **Step 4: Run the test, expect pass** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Exporter"
  ```
  Expected: `nilTaskJournalEntryExportsNilTaskID` green and the existing `fullRoundtrip`/`emptyStore`/`refusesNonEmptyDir` still pass at runtime.

  > **Expected intermediate broken build:** widening `taskID` to optional breaks `Importer.swift` `applyEntry` (~256), which subscripts `taskByID[dto.taskID]` with a now-optional key. **Do not patch `applyEntry` here.** Task 4 owns the full `applyEntry` rewrite (the owner-parameter version), and the orphan-skip loop it adds is what resolves the task. Commit Task 3 with the `Importer` target in this transient non-compiling state and proceed directly into Task 4, which restores a clean build. (Run Task 3's Exporter test only after Task 4 lands if you want a fully green tree; the assertion itself is on the Exporter output, unaffected by the `Importer` break.)

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift
  git commit -m "fix(export): stop fabricating UUIDs for nil-task journal entries

Widen JournalEntryDTO/AttachmentDTO taskID to optional and emit the
real (possibly nil) owning-task id. Closes export-1. Leaves Importer's
applyEntry temporarily non-compiling; Task 4 rewrites it."
  ```

---

### Task 4: Skip orphan journal entries on import (import-2)

> **Transition from Task 3:** Task 3 widened `JournalEntryDTO.taskID` to `UUID?`, which left `Importer.applyEntry` non-compiling (it subscripts `taskByID[dto.taskID]` with an optional key). This task rewrites the journal-entry handling end to end — the orphan-skip loop resolves the owning task up front, and `applyEntry` becomes a pure setter taking an already-resolved `owner: LillistTask` — which both adds the import-2 behavior and restores a clean build. Start the tree in Task 3's transient broken state; finish this task green.

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` (the `for dto in document.journalEntries` loop inside `apply`'s `perform` block, and the `private nonisolated func applyEntry(_:into:taskByID:)` helper near the file's end — re-anchor by name; Wave 4 left both intact, so the current `applyEntry` body still reads `row.task = taskByID[dto.taskID]`)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (add two `@Test` methods)

- [ ] **Step 1: Write the failing test** — Append these two tests to `ImporterTests.swift` inside the struct (after the version tests added in Task 2). They reuse the `emptyDocument(version:)` helper added in Task 2 by building documents directly with an orphan journal entry:

```swift
    @Test("Journal entry with nil taskID is skipped and recorded")
    func nilTaskIDJournalEntrySkipped() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        var doc = emptyDocument(version: ExportSchema.version)
        let orphanID = UUID()
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: orphanID,
                taskID: nil,
                kind: JournalEntryKind.note.rawValue,
                body: "no owner",
                payload: nil,
                createdAt: Date(timeIntervalSince1970: 1),
                editedAt: nil
            )
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.journalEntriesInserted == 0)
        #expect(summary.journalEntriesSkipped == 1)
        #expect(summary.errors.count == 1)
        #expect(summary.errors[0].contains(orphanID.uuidString))
    }

    @Test("Journal entry referencing an absent task is skipped and recorded")
    func unresolvedTaskIDJournalEntrySkipped() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        var doc = emptyDocument(version: ExportSchema.version)
        let entryID = UUID()
        let danglingTaskID = UUID() // never appears in doc.tasks or the store
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: entryID,
                taskID: danglingTaskID,
                kind: JournalEntryKind.note.rawValue,
                body: "owner missing",
                payload: nil,
                createdAt: Date(timeIntervalSince1970: 2),
                editedAt: nil
            )
        ]
        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.journalEntriesInserted == 0)
        #expect(summary.journalEntriesSkipped == 1)
        #expect(summary.errors.count == 1)
        #expect(summary.errors[0].contains(entryID.uuidString))
    }
```

- [ ] **Step 2: Run the test, expect failure** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: both new tests fail. Today `applyEntry` resolves a missing/nil task to `row.task = nil` and the row is still *inserted* — so `journalEntriesInserted == 1` and `journalEntriesSkipped == 0`. Failure: `Expectation failed: summary.journalEntriesSkipped == 1` (actual 0).

- [ ] **Step 3: Implement the minimal change** — In `Importer.swift`, replace the `for dto in document.journalEntries` loop (inside `apply`'s `perform` block — re-anchor by the loop header, not a line number) with a version that resolves the task up front and skips orphans:

```swift
            for dto in document.journalEntries {
                // A journal entry must belong to a task. Entries with a
                // nil or unresolved taskID are orphans (CloudKit can
                // deliver dangling relationships, and older bundles may
                // predate referential cleanup) — skip them rather than
                // insert a task-less row.
                guard let taskID = dto.taskID, let owner = taskByID[taskID] else {
                    entriesSkipped += 1
                    errors.append("journalEntry \(dto.id): skipped (no resolvable task)")
                    continue
                }
                do {
                    if let existing = try self.fetchJournalEntry(id: dto.id, ctx: ctx) {
                        let action = self.decideAction(
                            policy: policy,
                            existingModified: existing.editedAt,
                            existingCreated: existing.createdAt,
                            incomingModified: dto.editedAt,
                            incomingCreated: dto.createdAt
                        )
                        switch action {
                        case .skip:
                            entriesSkipped += 1
                        case .update:
                            self.applyEntry(dto, into: existing, owner: owner)
                            entriesUpdated += 1
                        }
                    } else {
                        let row = JournalEntry(context: ctx)
                        row.id = dto.id
                        self.applyEntry(dto, into: row, owner: owner)
                        entriesInserted += 1
                    }
                } catch {
                    errors.append("journalEntry \(dto.id): \(error.localizedDescription)")
                }
            }
```

  And rewrite the `applyEntry` helper (the `private nonisolated func applyEntry(...)` near the file's end — currently non-compiling after Task 3 widened `taskID`) so the owner is passed in already-resolved (the entry loop now owns resolution, keeping `applyEntry` a pure setter):

```swift
    private nonisolated func applyEntry(_ dto: ExportSchema.JournalEntryDTO, into row: JournalEntry, owner: LillistTask) {
        row.task = owner
        row.kindRaw = Int16(dto.kind)
        row.body = dto.body
        row.payload = dto.payload
        row.createdAt = dto.createdAt
        row.editedAt = dto.editedAt
    }
```

  > Note: the `taskByID` dictionary is built from `document.tasks` during the `for dto in document.tasks` loop and also captures pre-existing rows found via `fetchTask`. An entry whose `taskID` matches a task already in the store *but absent from the bundle* will still be treated as unresolved, because `taskByID` only holds rows touched by this import. That is the correct conservative behavior for a manual-merge bundle: the bundle is the unit of truth for relationships it declares.

- [ ] **Step 4: Run the test, expect pass** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: `Suite "Importer" passed`; `nilTaskIDJournalEntrySkipped` and `unresolvedTaskIDJournalEntrySkipped` green; the existing merge-policy tests still pass.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Export/Importer.swift Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift
  git commit -m "fix(import): skip orphan journal entries instead of inserting task-less rows

Journal entries with a nil or unresolved taskID are counted in
journalEntriesSkipped and appended to errors. Closes import-2."
  ```

---

### Task 5: Truncated-JSON and transaction-contract tests (import-3 verification)

**Files:**
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (add three `@Test` methods + the `taskCount(in:)` helper)

These are pure tests — they verify behavior already guaranteed by the code (`importBundle` decodes, which throws on truncated input; `apply` is all-or-nothing) and lock the documented transaction contract from Task 2 against regression. No production code changes.

> **⚠️ Execution gotcha — why the save-failure test does NOT poison a nil-`id` object.**
> The model (`LillistModel.xcdatamodel/contents`) is a CloudKit model: **every** attribute is `optional="YES"`, there are **no** uniqueness constraints, and **no** `ManagedObjects/*+CoreData.swift` subclass overrides `validateForInsert`/`validateValue`/`willSave`. A `LillistTask` with `id == nil` therefore **saves successfully** — there is no save-time invariant on this model that a nil `id` (or any other missing attribute) violates. Mechanisms that *do* fault the model at save time on this schema — assigning a collection to a to-one relationship via KVC, or removing the persistent store out from under the context — surface as **Objective-C `NSException`s that terminate the test process**, not as catchable Swift `Error`s, so they can't be `catch`-asserted. The **one** mechanism that yields a catchable Swift error from `save()` is an **optimistic-locking merge conflict** under `NSMergePolicy.error`. But **after Wave 4 the Importer commits on `persistence.makeBackgroundContext()`** (no longer `viewContext`), and `makeBackgroundContext()` stamps the same trump merge policy (`mergeByPropertyObjectTrumpMergePolicyType`) with auto-merge ON — so a concurrent edit is trumped/auto-merged rather than raised as a conflict, and the `apply` `save()` still never throws on this model. (The conclusion is unchanged from the pre-Wave-4 `viewContext` analysis; only the context the save runs on changed.) Net: there is **no sound way to make the real `Importer.apply` background-context `save()` throw through the public API**. Task 5 Step 2 below therefore proves the transaction contract two honest ways instead — (a) by exercising the catchable merge-conflict rollback mechanism directly on a controllable pair of background contexts, and (b) by asserting structurally that `apply` stages every row into a single `perform`/`save` (so the commit is atomic by Core Data's own single-transaction guarantee). Do **not** reintroduce a nil-`id` poison object — it will save, the assertion will not fire, and you will be chasing a non-bug.

- [ ] **Step 1: Write the truncated-JSON test** — Append to `ImporterTests.swift` inside the struct:

```swift
    @Test("Truncated lillist.json throws a decoding error and persists nothing")
    func truncatedJSONThrows() async throws {
        // Produce a real, valid bundle then corrupt lillist.json by
        // chopping it mid-object so the decoder must fail.
        let src = try await TestStore.make()
        let srcTasks = TaskStore(persistence: src)
        _ = try await srcTasks.create(title: "Will be truncated")
        let bundle = try await exportFixture(from: src)

        let docURL = bundle.appendingPathComponent("lillist.json")
        let full = try Data(contentsOf: docURL)
        // Keep the opening brace + first ~12 bytes: structurally invalid JSON.
        let truncated = full.prefix(12)
        try truncated.write(to: docURL)

        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)
        do {
            _ = try await importer.importBundle(at: bundle, conflictPolicy: .skipExisting)
            Issue.record("expected a decoding error on truncated JSON")
        } catch is DecodingError {
            // Expected: JSONDecoder.decode throws DecodingError.
        } catch {
            Issue.record("expected DecodingError, got \(error)")
        }

        // The destination store must be untouched.
        let count = try await taskCount(in: dst)
        #expect(count == 0)
    }
```

- [ ] **Step 2: Write the transaction-contract tests** — The import's atomicity rests on two facts, and we assert each directly. **Chosen mechanism:** the all-or-nothing guarantee is Core Data's own single-`save()` transaction semantics — `apply` stages every row inside one background-context `perform { … try ctx.save() }` block (Wave 4 moved it off `viewContext` onto `makeBackgroundContext()`, but it is still a single `perform`/`save`), so the commit is atomic by construction. Because this permissive CloudKit model has no save-time invariant that throws *catchably* (see the gotcha above), we prove the contract two complementary, model-honest ways rather than poisoning a row:
>
> 1. **`saveFailureRollbackIsCatchable`** — exercises the *one* mechanism that produces a catchable Swift error from `save()` on this model (an optimistic-lock merge conflict under `NSMergePolicy.error`) on a controllable background-context pair, and confirms that after the failed save a `rollback()` leaves the store at its pre-edit baseline. This locks in the catchable-error → rollback behavior the documented contract (and the `background-context-seam` plan) depends on, without pretending the view-context path can be made to throw.
> 2. **`importIsSingleAtomicSave`** — proves structurally that a *successful* multi-row `apply` commits everything together: a valid bundle of several tasks + tags + journal entries imports, and the destination row counts match the bundle exactly (no partial subset). Combined with the single-`save()` block in `apply`, this is the positive half of "all or nothing": Core Data cannot persist a strict subset of one `save()`.

  Append both tests to `ImporterTests.swift` inside the struct:

```swift
    @Test("A catchable save failure can be rolled back to the pre-edit baseline (transaction-contract mechanism)")
    func saveFailureRollbackIsCatchable() async throws {
        // The only save() that throws a CATCHABLE Swift error on this
        // permissive CloudKit model is an optimistic-lock merge conflict
        // under NSMergePolicy.error (a nil id, a missing attribute, etc.
        // all save fine; KVC type-violations raise an NSException that
        // crashes the process). We reproduce that mechanism on two
        // background contexts we fully control, then prove rollback
        // restores the baseline — the rollback half of the import's
        // all-or-nothing contract.
        let p = try await TestStore.make()
        let id = UUID()

        // Seed a committed row through the view context.
        let main = p.container.viewContext
        await main.perform {
            let t = LillistTask(context: main)
            t.id = id
            t.title = "baseline"
            try? main.save()
        }

        let c1 = p.container.newBackgroundContext(); c1.mergePolicy = NSMergePolicy.error
        let c2 = p.container.newBackgroundContext(); c2.mergePolicy = NSMergePolicy.error

        // Both contexts mutate the same row off the same snapshot.
        await c1.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? c1.fetch(req).first)?.title = "edit-1"
        }
        await c2.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            (try? c2.fetch(req).first)?.title = "edit-2"
        }

        // First save wins; second save is now stale and throws a
        // catchable NSError (NSManagedObjectMergeError).
        let firstThrew: Bool = await c1.perform {
            do { try c1.save(); return false } catch { return true }
        }
        let secondThrew: Bool = await c2.perform {
            do { try c2.save(); return false } catch { return true }
        }
        #expect(firstThrew == false)
        #expect(secondThrew == true)

        // Rolling back the failed context drops its pending edit; the
        // committed store value (from c1) is what survives.
        await c2.perform { c2.rollback() }
        let after = try await fetchTitle(in: p, id: id)
        #expect(after == "edit-1")
    }

    @Test("A successful import commits every row in one transaction — no partial subset (transaction contract)")
    func importIsSingleAtomicSave() async throws {
        let dst = try await TestStore.make()
        let importer = Importer(persistence: dst)

        // A multi-row bundle: 2 tags, 3 tasks, 2 journal entries owned by
        // those tasks. A single ctx.save() commits all of them together —
        // Core Data cannot persist a strict subset of one transaction.
        var doc = emptyDocument(version: ExportSchema.version)
        let tagA = UUID(), tagB = UUID()
        let t1 = UUID(), t2 = UUID(), t3 = UUID()
        doc.tags = [
            ExportSchema.TagDTO(id: tagA, name: "Work", tintColor: "#FF0000", parentID: nil, position: 0),
            ExportSchema.TagDTO(id: tagB, name: "Home", tintColor: "#00FF00", parentID: nil, position: 1)
        ]
        func task(_ id: UUID, _ title: String, _ pos: Double, tags: [UUID]) -> ExportSchema.TaskDTO {
            ExportSchema.TaskDTO(
                id: id, title: title, notes: "", status: 0,
                start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
                position: pos, isPinned: false, parentID: nil, tagIDs: tags,
                createdAt: Date(timeIntervalSince1970: pos), modifiedAt: nil,
                closedAt: nil, deletedAt: nil
            )
        }
        doc.tasks = [
            task(t1, "Alpha", 0, tags: [tagA]),
            task(t2, "Beta", 1, tags: [tagB]),
            task(t3, "Gamma", 2, tags: [])
        ]
        doc.journalEntries = [
            ExportSchema.JournalEntryDTO(
                id: UUID(), taskID: t1, kind: JournalEntryKind.note.rawValue,
                body: "note on alpha", payload: nil,
                createdAt: Date(timeIntervalSince1970: 5), editedAt: nil
            ),
            ExportSchema.JournalEntryDTO(
                id: UUID(), taskID: t2, kind: JournalEntryKind.note.rawValue,
                body: "note on beta", payload: nil,
                createdAt: Date(timeIntervalSince1970: 6), editedAt: nil
            )
        ]

        let summary = try await importer.apply(document: doc, policy: .skipExisting)
        #expect(summary.tasksInserted == 3)
        #expect(summary.tagsInserted == 2)
        #expect(summary.journalEntriesInserted == 2)
        #expect(summary.errors.isEmpty)

        // The whole batch is visible in the store — all-or-nothing's
        // "all" half: a single save() committed every staged row.
        #expect(try await taskCount(in: dst) == 3)
    }
```

  Add the `taskCount(in:)` free helper next to the existing `fetchTitle` free function at the bottom of the file (the `private func fetchTitle(in:id:)` helper, now ~lines 187–194 after Wave 4 appended a test — anchor by the `fetchTitle` declaration, not a line number):

```swift
/// Count LillistTask rows in a store — used to prove all-or-nothing
/// import semantics.
private func taskCount(in p: PersistenceController) async throws -> Int {
    let ctx = p.container.viewContext
    return try await ctx.perform {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        return try ctx.count(for: req)
    }
}
```

  > **⚠️ Execution gotcha — `TagDTO`'s field order is `id, name, tintColor, parentID, position` (NOT `…position, parentID`).** The call sites above are written against the current `ExportSchema.swift`: `TagDTO(id:name:tintColor:parentID:position:)`, `TaskDTO` in its 16-field declaration order, and `JournalEntryDTO(id:taskID:kind:body:payload:createdAt:editedAt:)` with `taskID` as `UUID?` *after Task 3 widens it* (if Task 3 has not yet landed in your tree, `taskID` is still non-optional `UUID` — pass `t1`/`t2` directly, which compiles under both). `JournalEntryKind.note` is the plain-note case (`= 0`) and `.rawValue` is the `Int` the DTO's `kind` field wants. Re-Read `ExportSchema.swift` and `Model/JournalEntryKind.swift` before running and adjust if the structs have drifted — do not assume.

- [ ] **Step 3: Run the tests, expect pass** — There is no Red phase here; these tests lock in already-correct behavior (decode-throws + single-save atomicity). Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: `Suite "Importer" passed`; `truncatedJSONThrows`, `saveFailureRollbackIsCatchable`, and `importIsSingleAtomicSave` all green. If `saveFailureRollbackIsCatchable`'s `secondThrew` is `false`, the merge-conflict mechanism has stopped throwing — check that both background contexts still carry `NSMergePolicy.error` (a trump/last-wins policy silently resolves the conflict). If `importIsSingleAtomicSave` reports fewer rows than the bundle, that is a real atomicity regression — STOP and fix it in `apply` before proceeding. `background-context-seam` (Wave 4) already moved `apply` onto a `newBackgroundContext` and added `context.rollback()` in the mutating-`perform` catch; that move must preserve single-`save()` atomicity, so a partial subset means the seam move broke it and the seam code is what to repair — never relax this assertion.

- [ ] **Step 4: Run the full LillistCore suite** — Confirm no regression across the package:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expected: all suites pass, including `Importer`, `Exporter`, `LillistError`. Treat any warning as an error (none expected from these changes).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift
  git commit -m "test(import): lock truncated-JSON rejection and single-save atomicity

Truncated lillist.json throws DecodingError and persists nothing; a
multi-row import commits every row in one transaction, and the
catchable merge-conflict rollback mechanism the contract depends on is
exercised directly. Verifies import-3 contract."
  ```

---

## Cross-plan coordination

- **HARD DEPENDENCY — `background-context-seam` (Wave 4) lands first.** It is two waves ahead of this plan, so by the time you execute here it is already on `main`: it has moved `buildDocument` and `apply` off `viewContext` onto a `newBackgroundContext` and added `context.rollback()` in the mutating `perform` catch. This plan's edits all live **inside** the moved `apply`/`buildDocument` bodies, so re-anchor onto the relocated code (use the Pre-flight Re-Read; `apply` no longer reads `persistence.container.viewContext` — it builds a background context):
  - **Version guard** stays *before* the `perform` block, exactly as written in Task 2 — it touches no Core Data, so the surrounding context change is irrelevant to it. Insert it as the first statements of `apply`, ahead of whatever `newBackgroundContext`/`perform` the seam plan introduced.
  - **Orphan-skip loop** (Task 4) is context-agnostic — it operates on `taskByID` and the DTOs, not on the context object — so transplant it verbatim into the moved journal-entry loop.
  - **`m.task?.id` map sites** (Task 3) are likewise inside `buildDocument`'s `perform`; apply the one-character edits at their moved positions.
  - **Tests:** Task 5's `importIsSingleAtomicSave` asserts the seam plan preserved single-`save()` atomicity after the move; `saveFailureRollbackIsCatchable` locks in the catchable merge-conflict → rollback behavior that the seam plan's own `context.rollback()` in the mutating-`perform` catch now implements on the production path. Both must stay green against the post-seam context model — if `importIsSingleAtomicSave` ever sees a partial row subset, that is a real atomicity regression in the seam plan's move; STOP and fix the seam, do not relax the assertion.

- **`link-preview-ssrf-guards` [P1]** owns the deterministic malformed-HTML assertion fix (`OpenGraphParserTests.swift:44`, the `m.title == "Broken" || m.title == nil` disjunction) and the `test-2` link-preview negative tests. Although the P3 roadmap line groups "deterministic malformed-HTML test" under item 17, that assertion is in the LinkPreview lane's files, outside this plan's Export/Validation scope and outside its finding IDs (import-1/2/3, export-1). This plan does **not** touch it. Flagged in the manifest so it is not double-owned.

---

## Self-review checklist

- [ ] **import-1** (guard `document.version` before `apply()`: accept equal, upgrade older, throw typed error for newer; tests for newer/equal/down-level) — closed by **Task 1** (adds `LillistError.unsupportedExportVersion`) + **Task 2** (the guard + `versionEqualApplies`/`versionOlderApplies`/`versionNewerThrows` tests).
- [ ] **import-2** (skip journal entries whose `taskID` does not resolve; append to `errors`, increment `journalEntriesSkipped`) — closed by **Task 4** (orphan-skip loop + `nilTaskIDJournalEntrySkipped`/`unresolvedTaskIDJournalEntrySkipped` tests).
- [ ] **import-3** (decide + document the import transaction contract; transaction-contract tests; plus truncated-JSON test) — closed by **Task 2** (documents the all-or-nothing contract in `apply`'s doc comment) + **Task 5** (`truncatedJSONThrows`, plus `saveFailureRollbackIsCatchable` and `importIsSingleAtomicSave` — the model has no catchable view-context save-time invariant, so the contract is proven via the merge-conflict rollback mechanism and single-save atomicity rather than a nil-`id` poison object; see the Task 5 gotcha).
- [ ] **export-1** (Exporter omits nil-task entries instead of fabricating a random UUID) — closed by **Task 3** (widen `taskID` to optional, emit `m.task?.id`, `nilTaskJournalEntryExportsNilTaskID` test); Task 4 then rewrites `applyEntry` to take a resolved owner.
- [ ] **Strengths preserved:** the airtight DTO boundary (no `NSManagedObject` escapes — all changes stay value-type DTOs), `@testable import`-reachable construction, `.iso8601` Codable contract, and Swift Testing framework/helpers (`TestStore`, `tempDir`, `exportFixture`) are all retained; no synchronous-AsyncStream or Calendar-date-math code is touched.
- [ ] **Out of scope (DRY/YAGNI):** the malformed-HTML disjunction (link-preview lane), the background-context move (`background-context-seam`), and attachment *import* copy-back (explicitly deferred in `Importer`'s header comment) are not done here.
