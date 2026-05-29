# Export/Import Robustness Implementation Plan

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

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` (`apply(document:policy:)` lines 81-83 — insert the guard at the very top, before reading `viewContext`)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (add three `@Test` methods)

- [ ] **Step 1: Write the failing test** — Append these three tests to `ImporterTests.swift` inside the `ImporterTests` struct (after `invalidBundle()`, before the closing `}` on line 154). They construct an `ExportSchema.Document` directly (the synthesized memberwise init is reachable via `@testable import LillistCore`):

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

- [ ] **Step 3: Implement the minimal change** — In `Importer.swift`, insert the guard as the first statements of `apply(document:policy:)`. Replace lines 81-83:

```swift
    public func apply(document: ExportSchema.Document, policy: ConflictPolicy) async throws -> ImportSummary {
        let ctx = persistence.container.viewContext
        return try await ctx.perform { [policy, self] in
```

  with:

```swift
    /// Apply a decoded export `document` to the store.
    ///
    /// ## Transaction contract (import-3)
    ///
    /// This is **all-or-nothing**: every row is staged in a single
    /// `viewContext.perform` block and committed by one `ctx.save()` at
    /// the end. If that save throws, the error propagates and *nothing*
    /// is persisted — the returned `ImportSummary` (including its
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
        let ctx = persistence.container.viewContext
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
- Modify `Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift` (`JournalEntryDTO.taskID` line 46; `AttachmentDTO.taskID` line 56)
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift` (journal map line 86; attachment map line 106)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift` (add one `@Test`)

- [ ] **Step 1: Write the failing test** — Append this test to `ExporterTests.swift` inside the `ExporterTests` struct (after `refusesNonEmptyDir()`, before the closing `}` on line 89). It creates a journal entry, then nulls its `task` relationship directly (simulating an orphan that synced/corruption can produce) and asserts the export carries `taskID == nil` rather than a fabricated UUID:

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

  (a) In `ExportSchema.swift`, widen the two `taskID` fields. Change `JournalEntryDTO.taskID` (line 46):

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

  Change `AttachmentDTO.taskID` (line 56):

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

  (b) In `Exporter.swift`, stop fabricating. Change the journal map (line 86) from `taskID: m.task?.id ?? UUID(),` to `taskID: m.task?.id,`:

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

  And the attachment map (line 106) from `taskID: m.task?.id ?? UUID(),` to `taskID: m.task?.id,`:

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

- [ ] **Step 4: Run the test, expect pass** — Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Exporter"
  ```
  Expected: `Suite "Exporter" passed`; `nilTaskJournalEntryExportsNilTaskID` green and the existing `fullRoundtrip`/`emptyStore`/`refusesNonEmptyDir` still pass. (The Importer's `applyEntry` at line 256 — `row.task = taskByID[dto.taskID]` — still compiles because `Importer` is fixed in Task 4; if running Exporter-only here it must still build. Note: this step changes `applyEntry`'s `dto.taskID` to optional, breaking that subscript. Sequence Task 4 immediately after — or, to keep the tree compiling at every commit, fold the one-line `applyEntry` fix into THIS commit since it is forced by the type change.)

  To keep the build green at this commit, also apply the forced one-line fix in `Importer.swift` `applyEntry` (line 256). Change:

```swift
    private nonisolated func applyEntry(_ dto: ExportSchema.JournalEntryDTO, into row: JournalEntry, taskByID: [UUID: LillistTask]) {
        row.task = dto.taskID.flatMap { taskByID[$0] }
        row.kindRaw = Int16(dto.kind)
        row.body = dto.body
        row.payload = dto.payload
        row.createdAt = dto.createdAt
        row.editedAt = dto.editedAt
    }
```

  Re-run the command above; expected `Suite "Exporter" passed` and a clean build (the `Importer` target now compiles against the optional `taskID`).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Export/ExportSchema.swift Packages/LillistCore/Sources/LillistCore/Export/Exporter.swift Packages/LillistCore/Sources/LillistCore/Export/Importer.swift Packages/LillistCore/Tests/LillistCoreTests/Export/ExporterTests.swift
  git commit -m "fix(export): stop fabricating UUIDs for nil-task journal entries

Widen JournalEntryDTO/AttachmentDTO taskID to optional and emit the
real (possibly nil) owning-task id. applyEntry resolves nil-safely.
Closes export-1."
  ```

---

### Task 4: Skip orphan journal entries on import (import-2)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Export/Importer.swift` (journal-entry loop lines 165-191)
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

- [ ] **Step 3: Implement the minimal change** — In `Importer.swift`, replace the journal-entry loop (lines 165-191) with a version that resolves the task up front and skips orphans:

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

  And replace the `applyEntry` helper (the version edited in Task 4 Step 4 — lines 255-262) so the owner is passed in already-resolved (the entry loop now owns resolution, keeping `applyEntry` a pure setter):

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

  > Note: the `taskByID` dictionary is built from `document.tasks` during the task loop (lines 130-159) and also captures pre-existing rows found via `fetchTask`. An entry whose `taskID` matches a task already in the store *but absent from the bundle* will still be treated as unresolved, because `taskByID` only holds rows touched by this import. That is the correct conservative behavior for a manual-merge bundle: the bundle is the unit of truth for relationships it declares.

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

### Task 5: Truncated-JSON and mid-batch-failure tests (import-3 verification)

**Files:**
- Test `Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift` (add two `@Test` methods)

These are pure tests — they verify behavior already guaranteed by the code (`importBundle` decodes, which throws on truncated input; `apply` is all-or-nothing) and lock the documented transaction contract from Task 2 against regression. No production code changes.

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

- [ ] **Step 2: Write the mid-batch-failure test** — Append to `ImporterTests.swift` inside the struct. A `kind` value out of `Int16` range forces `Int16(dto.kind)` to trap before save would even run — so instead we force the *save* to fail by violating a model constraint the apply path can't catch: insert a task that references itself as parent via a malformed second pass is not reachable. The deterministic, model-honest way to force a `ctx.save()` failure is a duplicate primary value that Core Data rejects only at save time. We seed the destination with a tag, then import a bundle whose tag carries a name the model marks unique — but the model has no such constraint. The robust approach: inject a save failure by importing a journal-entry `payload` is fine; instead we assert the contract structurally by importing a valid multi-row bundle into a destination whose context we have pre-poisoned with an unsaved invalid object, so the trailing `ctx.save()` throws and the *import's* rows roll back with it:

```swift
    @Test("A save failure aborts the whole import — no rows persist (transaction contract)")
    func midBatchSaveFailureRollsBackEverything() async throws {
        let dst = try await TestStore.make()

        // Poison the destination's viewContext with an invalid pending
        // object: a LillistTask missing its required `id`. Core Data
        // validates on save, so the Importer's trailing ctx.save() will
        // throw — and because the whole import shares this one context,
        // its staged rows must roll back too.
        let ctx = dst.container.viewContext
        try await ctx.perform {
            let bad = LillistTask(context: ctx)
            bad.title = "missing required id"
            bad.statusRaw = 0
            bad.position = 0
            bad.createdAt = Date(timeIntervalSince1970: 0)
            // Deliberately leave bad.id == nil so validateForInsert fails.
        }

        let importer = Importer(persistence: dst)
        var doc = emptyDocument(version: ExportSchema.version)
        doc.tasks = [
            ExportSchema.TaskDTO(
                id: UUID(),
                title: "should not survive",
                notes: "",
                status: 0,
                start: nil,
                startHasTime: false,
                deadline: nil,
                deadlineHasTime: false,
                position: 1,
                isPinned: false,
                parentID: nil,
                tagIDs: [],
                createdAt: Date(timeIntervalSince1970: 10),
                modifiedAt: nil,
                closedAt: nil,
                deletedAt: nil
            )
        ]

        do {
            _ = try await importer.apply(document: doc, policy: .skipExisting)
            Issue.record("expected ctx.save() to throw on the invalid pending object")
        } catch {
            // Expected: a Core Data validation error from save().
        }

        // Roll the failed context back so the count query sees a clean
        // baseline, then confirm nothing from the import persisted.
        try await ctx.perform { ctx.rollback() }
        let count = try await taskCount(in: dst)
        #expect(count == 0)
    }
```

  Add the `taskCount(in:)` free helper next to `fetchTitle` at the bottom of the file (after line 169):

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

- [ ] **Step 3: Run the tests, expect pass** — There is no Red phase here; these tests lock in already-correct behavior (decode-throws + single-save atomicity). Command:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "Importer"
  ```
  Expected: `Suite "Importer" passed`; `truncatedJSONThrows` and `midBatchSaveFailureRollsBackEverything` green. If `midBatchSaveFailureRollsBackEverything` does NOT throw, that is a real defect in the transaction contract — STOP and reconcile with the `background-context-seam` plan owner before changing anything (they may have moved `apply` to a background context with `context.rollback()` in the catch, which changes the seam).

- [ ] **Step 4: Run the full LillistCore suite** — Confirm no regression across the package:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore
  ```
  Expected: all suites pass, including `Importer`, `Exporter`, `LillistError`. Treat any warning as an error (none expected from these changes).

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Tests/LillistCoreTests/Export/ImporterTests.swift
  git commit -m "test(import): lock truncated-JSON rejection and all-or-nothing rollback

Truncated lillist.json throws DecodingError and persists nothing; a
save failure aborts the whole import. Verifies import-3 contract."
  ```

---

## Cross-plan coordination

- **`background-context-seam` [P2]** also edits `Export/Exporter.swift` and `Export/Importer.swift` — it moves `buildDocument` and `apply` off `viewContext` onto a `newBackgroundContext` and adds `context.rollback()` in the mutating `perform` catch. My edits live **inside** the same `apply`/`buildDocument` bodies (version guard at the top of `apply`; the journal-entry loop; the `m.task?.id` map sites). Land order matters: if `background-context-seam` lands first, the version guard still belongs *before* the `perform` block (it does not touch Core Data) and the orphan-skip loop is context-agnostic — re-apply onto the moved body. If THIS plan lands first, the seam plan must preserve the version guard placement and the orphan-skip loop verbatim. The `midBatchSaveFailureRollsBackEverything` test in Task 5 asserts the rollback contract both plans depend on — coordinate so it passes under whichever context model wins. Flagged in the manifest.

- **`link-preview-ssrf-guards` [P1]** owns the deterministic malformed-HTML assertion fix (`OpenGraphParserTests.swift:44`, the `m.title == "Broken" || m.title == nil` disjunction) and the `test-2` link-preview negative tests. Although the P3 roadmap line groups "deterministic malformed-HTML test" under item 17, that assertion is in the LinkPreview lane's files, outside this plan's Export/Validation scope and outside its finding IDs (import-1/2/3, export-1). This plan does **not** touch it. Flagged in the manifest so it is not double-owned.

---

## Self-review checklist

- [ ] **import-1** (guard `document.version` before `apply()`: accept equal, upgrade older, throw typed error for newer; tests for newer/equal/down-level) — closed by **Task 1** (adds `LillistError.unsupportedExportVersion`) + **Task 2** (the guard + `versionEqualApplies`/`versionOlderApplies`/`versionNewerThrows` tests).
- [ ] **import-2** (skip journal entries whose `taskID` does not resolve; append to `errors`, increment `journalEntriesSkipped`) — closed by **Task 4** (orphan-skip loop + `nilTaskIDJournalEntrySkipped`/`unresolvedTaskIDJournalEntrySkipped` tests).
- [ ] **import-3** (decide + document the import transaction contract; mid-batch-failure test; plus truncated-JSON test) — closed by **Task 2** (documents the all-or-nothing contract in `apply`'s doc comment) + **Task 5** (`midBatchSaveFailureRollsBackEverything` and `truncatedJSONThrows`).
- [ ] **export-1** (Exporter omits nil-task entries instead of fabricating a random UUID) — closed by **Task 3** (widen `taskID` to optional, emit `m.task?.id`, nil-safe `applyEntry`, `nilTaskJournalEntryExportsNilTaskID` test).
- [ ] **Strengths preserved:** the airtight DTO boundary (no `NSManagedObject` escapes — all changes stay value-type DTOs), `@testable import`-reachable construction, `.iso8601` Codable contract, and Swift Testing framework/helpers (`TestStore`, `tempDir`, `exportFixture`) are all retained; no synchronous-AsyncStream or Calendar-date-math code is touched.
- [ ] **Out of scope (DRY/YAGNI):** the malformed-HTML disjunction (link-preview lane), the background-context move (`background-context-seam`), and attachment *import* copy-back (explicitly deferred in `Importer`'s header comment) are not done here.
