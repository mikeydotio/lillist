# Extension Persistence Unification & Share/Intent Correctness Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 6.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> ⚠️ **Wave 1 (`store-swap-safety`) is merged to `main`.** It changed several shared files (`MigrationCoordinator`, `PersistenceHost`, `QuarantineManager`, `MigrationJournal`, both `AppEnvironment`s, `PersistenceController`). **Re-Read every file before editing and anchor by code structure — the line numbers in this plan may have drifted.**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route every extension Core Data access through the single gated `IntentSupport.makePersistence()` factory (cached per-process), bound the `suggestedEntities` fetch, propagate Share-Extension link-attachment failures, and resolve the dead helper-intent surface — all backed by co-compiled pure-helper unit tests.

**Architecture:** Today `TaskEntityQuery` has its own ungated persistence factory that opens the App-Group store with CloudKit mirroring even in LocalOnly and races a half-swapped store mid-migration (`ext-1`), while every other intent already funnels through `IntentSupport.makePersistence()` which consults `MigrationGate`. We delete the divergent factory and let `entities`/`suggestedEntities` propagate `storeUnavailable` (they already `throws`). `IntentSupport` gains a per-process `PersistenceController` cache keyed on the gate-resolved `SyncMode` (the only thing that varies between calls; `StoreConfiguration` isn't `Equatable`) so the controller is rebuilt only when sync-mode actually changes (`ext-2`). `SmartFilterStore.evaluate(group:)` gains an optional `limit` so `suggestedEntities` fetches only ~20 rows instead of materializing every open task and slicing (`ext-3`). `ShareRootView.save()` stops swallowing link-attachment failures, records them into `saveError`, and remembers the already-created task so a retry attaches the link without duplicating the task (`ext-4`). The two no-op "open app" indirection intents are collapsed into the single discoverable `openAppWhenRun` intents that deliver the only behavior they actually have (`ext-5`). The divergent decision logic (Share save flow, suggested-entities limit) is lifted into pure helpers co-compiled into the standalone iOS test bundle via `project.yml` `sources` paths (`ext-6`).

**Tech Stack:** Swift 6.2, AppIntents, Core Data via `NSPersistentCloudKitContainer`, App Group `group.io.mikeydotio.Lillist`, XCTest (iOS app test bundle — standalone, no `@testable import`), Swift Testing (`import Testing`, LillistCore package tests), xcodegen.

**Source findings:** ext-1, ext-2, ext-3, ext-4, ext-5, ext-6.

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Extensions/ShareExtension-iOS/ShareSaveFlow.swift` | Pure helper enum `ShareSaveFlow` modelling the create-then-attach decision (`ext-4`, `ext-6`): given the current saved-task ID, decide whether to create a new task or reuse the existing one, and report whether a link attachment must be attached. No SwiftUI, no `@State`. |
| `Apps/Lillist-iOS/Tests/UnitTests/ShareSaveFlowTests.swift` | XCTest unit tests for `ShareSaveFlow` (co-compiled, `ext-6`): proves retry after a link-attachment failure reuses the saved task instead of creating a second one, and that a first save creates a task. |
| `Apps/Lillist-iOS/Tests/IntegrationTests/SuggestedEntitiesLimitTests.swift` | XCTest integration test (`ext-3`): seeds >20 open tasks against an in-memory store and asserts the limit-aware `SmartFilterStore.evaluate(group:limit:)` returns exactly the requested cap. |

### Modify

| Path | Responsibility |
|------|----------------|
| `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift` | Delete the divergent `makePersistence()`; route both `entities(for:)` and `suggestedEntities()` through `IntentSupport.makePersistence()`; call the new limit-aware evaluate (`ext-1`, `ext-3`). |
| `Extensions/ShortcutsActions/IntentSupport.swift` | Add a per-process `PersistenceController` cache keyed on the gate-resolved `SyncMode` (`ext-2`). |
| `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` | Add an optional `limit: Int? = nil` parameter to the existing `evaluate(group:…)` overload, applying it as `fetchLimit` (`ext-3`). **Shared file — coordinate with `fractional-ordering-compaction`.** |
| `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift` | Add a Swift Testing case asserting `evaluate(group:limit:)` caps the result count (`ext-3`). |
| `Extensions/ShareExtension-iOS/ShareRootView.swift` | Use `ShareSaveFlow` to drive create-vs-reuse; change link attachment from `try?` to `try`; propagate failures into `saveError`; keep the sheet open for retry without re-creating the task (`ext-4`). |
| `Extensions/ShortcutsActions/OpenTaskIntent.swift` | Remove the dead `OpenTaskInAppIntent` indirection; collapse `OpenTaskIntent` to a single `openAppWhenRun` intent (`ext-5`). |
| `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift` | Remove the dead `OpenAtQuickCaptureIntent` indirection; collapse `QuickCaptureLockScreenIntent` to a single `openAppWhenRun` intent (`ext-5`). |
| `Apps/Lillist-iOS/project.yml` | Add `Extensions/ShareExtension-iOS/ShareSaveFlow.swift` to the `Lillist-iOSTests` target `sources` so the new pure helper compiles into the standalone test bundle (`ext-6`). |

---

## Task 1: Add a limit-aware `evaluate(group:)` overload to `SmartFilterStore` (ext-3)

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift` (append a `@Test` to the existing evaluate suite — add after the `evaluateExcludesArchivedByDefault` test, around line 199+).
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift` lines 291–311 (the `evaluate(group:sort:ascending:now:calendar:includeArchived:)` overload).

> **Shared-file note:** `SmartFilterStore.swift` is also edited by `fractional-ordering-compaction` (the `reorder` path, lines ~230–259). This task only adds a parameter to the `evaluate(group:)` overload (lines 291–311) and does not touch `reorder`. Land whichever plan goes first; the other rebases on a non-overlapping region.

- [ ] **Step 1: Write the failing test.** Append this `@Test` to `SmartFilterStoreTests.swift` immediately after the existing `evaluate respects sort field and direction` test (after line 197). It uses the same `import Testing` / `TestStore.make()` style as the surrounding suite.

```swift
    @Test("evaluate(group:limit:) caps the number of returned rows")
    func evaluateRespectsLimit() async throws {
        let controller = try await TestStore.make()
        let smartStore = SmartFilterStore(persistence: controller)
        let taskStore = TaskStore(persistence: controller)
        for i in 0..<25 {
            _ = try await taskStore.create(title: "Open task \(i)")
        }
        let group = PredicateGroup(combinator: .all, predicates: [
            .leaf(.init(field: .inTrash, op: .is, value: .bool(false)))
        ])
        let capped = try await smartStore.evaluate(group: group, limit: 20)
        #expect(capped.count == 20)
        let uncapped = try await smartStore.evaluate(group: group)
        #expect(uncapped.count == 25)
    }
```

- [ ] **Step 2: Run the test, expect failure.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SmartFilterStoreTests
  ```
  Expected: compile failure — `error: incorrect argument label in call (have 'group:limit:', expected 'group:sort:ascending:now:calendar:includeArchived:')` (the `limit:` parameter does not exist yet).

- [ ] **Step 3: Implement the minimal change.** In `SmartFilterStore.swift`, replace the existing `evaluate(group:…)` overload (lines 291–311) with this version that adds the `limit` parameter and applies it as `fetchLimit`:

```swift
    public func evaluate(
        group: PredicateGroup,
        sort: SortField = .modifiedAt,
        ascending: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current,
        includeArchived: Bool = false,
        limit: Int? = nil
    ) async throws -> [TaskStore.TaskRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicateCompiler.compile(
                group,
                now: now,
                calendar: calendar,
                includeArchived: includeArchived
            )
            req.sortDescriptors = Self.sortDescriptors(field: sort, ascending: ascending)
            if let limit, limit > 0 {
                req.fetchLimit = limit
            }
            let tasks = try context.fetch(req)
            return tasks.map { Self.record(from: $0) }
        }
    }
```

  Also update the doc comment immediately above it (lines 282–290) to mention the new parameter — replace the existing doc comment block with:

```swift
    /// Evaluate an ad-hoc `PredicateGroup` (one that hasn't been persisted as
    /// a `SmartFilter`) and return matching `TaskStore.TaskRecord`s. Used by
    /// iOS Search and any caller that needs to run a filter without first
    /// saving it.
    ///
    /// Archived rows (`archivedAt != nil`) are excluded by default; pass
    /// `includeArchived: true` to surface them — the iOS Tasks view does
    /// this when the `.done` quick filter is selected so the "history"
    /// view shows everything completed.
    ///
    /// Pass `limit` to bound the fetch at the SQLite level (`fetchLimit`)
    /// rather than materializing every match and slicing afterwards — the
    /// Shortcuts `suggestedEntities` path uses this to fetch only the most
    /// recent ~20 tasks. A non-positive `limit` is ignored (unbounded).
```

- [ ] **Step 4: Run the test, expect pass.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter SmartFilterStoreTests
  ```
  Expected: `Test run with N tests passed` (including `evaluate(group:limit:) caps the number of returned rows`). No new warnings.

- [ ] **Step 5: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift \
          Packages/LillistCore/Tests/LillistCoreTests/Stores/SmartFilterStoreTests.swift
  git commit -m "feat(core): add limit-aware SmartFilterStore.evaluate(group:) overload

Bounds the ad-hoc predicate evaluation at the SQLite fetchLimit level so
the Shortcuts suggestedEntities path can fetch only ~20 rows instead of
materializing every open task and slicing in memory. Closes ext-3."
  ```

---

## Task 2: Cache one per-process `PersistenceController` behind the gate (ext-2)

**Files:**
- Modify: `Extensions/ShortcutsActions/IntentSupport.swift` (whole file, currently lines 1–24).

> This change has no standalone unit test of its own — `IntentSupport` lives in a signed-extension target that the standalone iOS test bundle cannot `@testable import` (see the note in `AppIntentHandlerTests.swift`). The cache is verified indirectly: Task 3's `TaskEntityQuery` routes through it, and the existing `AppIntentHandlerTests` exercise the same gated handler path. Correctness here is by construction (read the gate every call; reuse the controller only when the resolved sync mode is unchanged). The build of the extension target via the iOS scheme is the gate against regressions.
>
> **Cache key is `SyncMode`, not `StoreConfiguration`.** `StoreConfiguration` is declared only `Sendable`, *not* `Equatable` (verified in `Packages/LillistCore/Sources/LillistCore/Persistence/StoreConfiguration.swift:15`), and its nested `StoreKind` carries a `URL` — making it unsuitable as a cache key without adding conformances to a shared persistence type (out of scope; risks cross-plan collisions). `SyncMode` is a `String`-backed enum (`SyncMode.swift:14: public enum SyncMode: String, Codable, Sendable, CaseIterable`) and is therefore automatically `Equatable`. The App-Group store path is fixed for the process, so the only thing that changes between calls is the mode — keying on `SyncMode` is both correct and cheap. We use `gate.evaluate()` directly (rather than `resolveStoreConfiguration`) so we get the resolved `SyncMode` for the cache key and the abort message in one pass.

- [ ] **Step 1: Implement the cache.** Replace the entire contents of `Extensions/ShortcutsActions/IntentSupport.swift` with:

```swift
import Foundation
import AppIntents
import LillistCore

/// Shared helpers for App Intent `perform()` bodies.
enum IntentSupport {
    static let appGroupID = "group.io.mikeydotio.Lillist"

    /// Per-process cache so repeated intent invocations in the same
    /// extension process reuse one `PersistenceController` (and its open
    /// Core Data stack) instead of standing up a fresh container — and a
    /// fresh CloudKit mirroring subscription — on every call. The cache is
    /// keyed on the gate-resolved `SyncMode`: the App-Group store path is
    /// fixed for the process, so the only thing that changes between calls
    /// is the mode. If the user flips sync mode between invocations the key
    /// differs and we rebuild rather than serve a stale-mode controller.
    /// (`StoreConfiguration` itself isn't `Equatable`; `SyncMode` is a
    /// raw-value enum and is.)
    private actor Cache {
        static let shared = Cache()
        private var mode: SyncMode?
        private var controller: PersistenceController?

        func controller(
            mode: SyncMode,
            configuration: StoreConfiguration
        ) async throws -> PersistenceController {
            if let controller, self.mode == mode {
                return controller
            }
            let fresh = try await PersistenceController(configuration: configuration)
            self.mode = mode
            self.controller = fresh
            return fresh
        }
    }

    /// Plan 21: consult `MigrationGate` so the intent doesn't race a
    /// foreground sync-mode migration. When the gate says abort, the
    /// intent throws `LillistError.storeUnavailable` with the user-facing
    /// message so Shortcuts surfaces "Sync settings are being changed. Try
    /// again in a moment." instead of running against a half-swapped store.
    ///
    /// The gate is consulted on *every* call (cheap; reads the journal +
    /// mode store) so a migration in flight is always caught. Only the
    /// resulting `PersistenceController` is cached — and only while the
    /// gate keeps resolving the same `SyncMode`.
    static func makePersistence() async throws -> PersistenceController {
        let modeStore = SyncModeStore(appGroupID: appGroupID)
        guard let journal = FileMigrationJournalStore(appGroupID: appGroupID) else {
            throw LillistError.storeUnavailable(reason: "App Group container '\(appGroupID)' is not available.")
        }
        let gate = MigrationGate(journal: journal, modeStore: modeStore)
        switch await gate.evaluate() {
        case .abort(let message):
            throw LillistError.storeUnavailable(reason: message)
        case .proceed(let mode):
            guard let config = StoreConfiguration.appGroupOnDisk(
                groupID: appGroupID,
                syncMode: mode
            ) else {
                throw LillistError.storeUnavailable(
                    reason: "App Group container '\(appGroupID)' is not available."
                )
            }
            return try await Cache.shared.controller(mode: mode, configuration: config)
        }
    }
}
```

- [ ] **Step 2: Verify the extension target compiles.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
  ```
  Expected: `** BUILD SUCCEEDED **`, with the `ShortcutsActions` target compiling `IntentSupport.swift` with zero warnings. (`MigrationGate.evaluate()` returns `Decision.proceed(mode:)` / `.abort(message:)` and `StoreConfiguration.appGroupOnDisk(groupID:syncMode:)` returns an optional — both verified in the LillistCore source — so the switch and `guard let` compile cleanly.)

- [ ] **Step 3: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShortcutsActions/IntentSupport.swift
  git commit -m "perf(ext): cache one per-process PersistenceController behind the gate

IntentSupport.makePersistence() now reuses a single PersistenceController
(and its open Core Data + CloudKit stack) across intent invocations in the
same extension process, rebuilding only when the gate-resolved
StoreConfiguration changes. The MigrationGate is still consulted on every
call so a migration in flight is always caught. Closes ext-2."
  ```

---

## Task 3: Route `TaskEntityQuery` through the gated factory + limit the suggestions (ext-1, ext-3)

**Files:**
- Modify: `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift` (whole file, currently lines 1–44).

> Like `IntentSupport`, `TaskEntityQuery` is in the signed-extension target and cannot be `@testable import`-ed from the standalone test bundle. Its behavior is verified by construction (it now calls the same gated factory every other intent uses) plus the build. The limit-aware fetch it now depends on is independently tested in Task 1 (`evaluateRespectsLimit`) and Task 6 (`SuggestedEntitiesLimitTests`).

- [ ] **Step 1: Rewrite `TaskEntityQuery` to use the gated factory and the limit-aware evaluate.** Replace the entire contents of `Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift` with:

```swift
import AppIntents
import LillistCore

/// Looks up tasks by ID and produces recent-task suggestions for Shortcuts.
///
/// Persistence is acquired through `IntentSupport.makePersistence()`, the
/// single gated factory every Lillist intent shares: it consults
/// `MigrationGate` (so a foreground sync-mode migration is never raced) and
/// honours the user's `syncMode` (so a LocalOnly user is never silently
/// opened with CloudKit mirroring attached). When the gate aborts, the
/// thrown `LillistError.storeUnavailable` propagates out of `entities` /
/// `suggestedEntities` — Shortcuts surfaces the "try again in a moment"
/// message instead of running against a half-swapped store.
struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [TaskEntity.ID]) async throws -> [TaskEntity] {
        let persistence = try await IntentSupport.makePersistence()
        let store = TaskStore(persistence: persistence)
        var out: [TaskEntity] = []
        for id in identifiers {
            if let record = try? await store.fetch(id: id) {
                out.append(TaskEntity(record))
            }
        }
        return out
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        let persistence = try await IntentSupport.makePersistence()
        let filters = SmartFilterStore(persistence: persistence)
        let recent = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false))),
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]
        )
        let records = try await filters.evaluate(
            group: recent,
            sort: .modifiedAt,
            ascending: false,
            limit: 20
        )
        return records.map(TaskEntity.init)
    }
}
```

- [ ] **Step 2: Verify the extension target compiles.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
  ```
  Expected: `** BUILD SUCCEEDED **`. `TaskEntityQuery.swift` compiles with no reference to the now-deleted `makePersistence()` static and no unused-result / unused-import warnings. (Task 1's overload must already be merged or in the working tree for `limit:` to resolve.)

- [ ] **Step 3: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShortcutsActions/Entities/TaskEntityQuery.swift
  git commit -m "fix(ext): route TaskEntityQuery through the gated persistence factory

Deletes TaskEntityQuery's divergent makePersistence() — which opened the
App-Group store with CloudKit mirroring attached even in LocalOnly and
could race a half-swapped store mid-migration — and routes both
entities(for:) and suggestedEntities() through the shared, gated
IntentSupport.makePersistence(). suggestedEntities now fetches at most 20
rows via the limit-aware evaluate instead of materializing every open task
and slicing. Closes ext-1, ext-3."
  ```

---

## Task 4: Extract `ShareSaveFlow` pure helper and co-compile it into the test bundle (ext-4, ext-6)

**Files:**
- Create: `Extensions/ShareExtension-iOS/ShareSaveFlow.swift`.
- Modify: `Apps/Lillist-iOS/project.yml` (the `Lillist-iOSTests` target `sources`, around lines 128–139).
- Create: `Apps/Lillist-iOS/Tests/UnitTests/ShareSaveFlowTests.swift`.

The bug (`ext-4`): `ShareRootView.save()` currently does `_ = try? await attachmentStore.addLinkPreview(...)`, silently swallowing any link-attachment failure, and always calls `taskStore.create` first — so a user who retries after a failure gets a *second* task. The fix needs a small piece of pure decision logic, extracted so the standalone test bundle (which cannot `@testable import` the share extension) can prove the retry semantics.

- [ ] **Step 1: Write the failing test.** Create `Apps/Lillist-iOS/Tests/UnitTests/ShareSaveFlowTests.swift`:

```swift
import XCTest
import Foundation

/// Unit tests for `ShareSaveFlow`, the pure decision helper extracted from
/// `ShareRootView.save()`. `ShareSaveFlow` is co-compiled into this
/// standalone test bundle (see project.yml) because the share extension
/// target can't be `@testable import`-ed without a signed app host.
///
/// The behavior under test: when the link attachment fails, the already-
/// created task must NOT be re-created on the user's retry — the flow must
/// reuse the saved task ID and attempt only the attachment.
final class ShareSaveFlowTests: XCTestCase {
    func test_firstSave_createsTaskAndRequestsAttachment_whenURLPresent() {
        let step = ShareSaveFlow.next(savedTaskID: nil, hasURL: true)
        switch step {
        case .createTask(attachLink: let attach):
            XCTAssertTrue(attach, "A first save with a URL must request the link attachment")
        case .attachLinkOnly:
            XCTFail("First save must create the task, not skip to attach-only")
        }
    }

    func test_firstSave_createsTaskWithoutAttachment_whenNoURL() {
        let step = ShareSaveFlow.next(savedTaskID: nil, hasURL: false)
        switch step {
        case .createTask(attachLink: let attach):
            XCTAssertFalse(attach, "A first save with no URL must not request an attachment")
        case .attachLinkOnly:
            XCTFail("First save must create the task, not skip to attach-only")
        }
    }

    func test_retryAfterAttachmentFailure_reusesSavedTask_doesNotCreateAgain() {
        let saved = UUID()
        let step = ShareSaveFlow.next(savedTaskID: saved, hasURL: true)
        switch step {
        case .createTask:
            XCTFail("Retry must NOT create a second task — the first one already exists")
        case .attachLinkOnly(taskID: let id):
            XCTAssertEqual(id, saved, "Retry must reuse the already-saved task ID")
        }
    }
}
```

- [ ] **Step 2: Run the test, expect failure.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests/ShareSaveFlowTests 2>&1 | tail -25
  ```
  Expected: compile failure — `error: cannot find 'ShareSaveFlow' in scope` (the helper does not exist yet and is not on the test target's source list).

- [ ] **Step 3: Implement the minimal change.** Create `Extensions/ShareExtension-iOS/ShareSaveFlow.swift`:

```swift
import Foundation

/// Pure decision helper extracted from `ShareRootView.save()` so the
/// create-then-attach retry semantics can be unit-tested from the
/// standalone iOS test bundle (which can't `@testable import` the signed
/// share extension target).
///
/// The share sheet stays open after a failed link attachment so the user
/// can retry. On that retry the task already exists, so we must *not*
/// create a second one — we only re-attempt the attachment. This enum
/// encodes exactly that branch.
enum ShareSaveFlow {
    /// The next action `save()` should take.
    enum Step: Equatable {
        /// No task has been created yet — create one, and (when
        /// `attachLink` is true) attach the link afterwards.
        case createTask(attachLink: Bool)
        /// The task already exists (a prior attempt created it and then
        /// the link attachment failed) — skip creation and only attach.
        case attachLinkOnly(taskID: UUID)
    }

    /// Decide the next step given the task ID created by a prior attempt
    /// (`nil` if none yet) and whether the payload carries a URL.
    static func next(savedTaskID: UUID?, hasURL: Bool) -> Step {
        if let savedTaskID {
            return .attachLinkOnly(taskID: savedTaskID)
        }
        return .createTask(attachLink: hasURL)
    }
}
```

  Then add the helper to the `Lillist-iOSTests` target's `sources` in `Apps/Lillist-iOS/project.yml`. Replace the existing co-compile block (lines 131–139) with this version that adds the `ShareSaveFlow.swift` entry:

```yaml
      # Co-compile the SharePayload source so the tests can exercise its
      # decode() logic without needing a separate ShareExtension test
      # bundle. SharePayload has no UIKit-only behavior when initialised
      # with the `items:` test seam.
      - path: ../../Extensions/ShareExtension-iOS/SharePayload.swift
      # Co-compile the ShareSaveFlow pure helper so the create-then-attach
      # retry semantics of ShareRootView.save() can be unit-tested without
      # a signed ShareExtension test host.
      - path: ../../Extensions/ShareExtension-iOS/ShareSaveFlow.swift
      # Co-compile the ReportCrashIntent source so its resolver helper
      # can be exercised from the standalone iOS test bundle without
      # needing a ShortcutsActions extension test host.
      - path: ../../Extensions/ShortcutsActions/ReportCrashIntent.swift
```

  Regenerate the iOS pbxproj so the new test source is picked up:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  ```

- [ ] **Step 4: Run the test, expect pass.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests/ShareSaveFlowTests 2>&1 | tail -25
  ```
  Expected: `Test Suite 'ShareSaveFlowTests' passed` with all 3 tests green (`** TEST SUCCEEDED **`).

- [ ] **Step 5: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShareExtension-iOS/ShareSaveFlow.swift \
          Apps/Lillist-iOS/Tests/UnitTests/ShareSaveFlowTests.swift \
          Apps/Lillist-iOS/project.yml \
          Apps/Lillist-iOS/Lillist-iOS.xcodeproj
  git commit -m "test(ext): extract ShareSaveFlow helper for create-then-attach retry

Lifts the create-vs-reuse decision out of ShareRootView.save() into a pure
ShareSaveFlow enum, co-compiled into the standalone iOS test bundle so the
retry semantics (a failed link attachment must not spawn a second task)
are unit-tested. Closes ext-6 for the Share flow."
  ```

---

## Task 5: Propagate link-attachment failure in `ShareRootView.save()` (ext-4)

**Files:**
- Modify: `Extensions/ShareExtension-iOS/ShareRootView.swift` (the `@State` declarations at lines 13–17 and the `save()` body at lines 63–98).

> `ShareRootView` is SwiftUI in the signed share extension and cannot be `@testable import`-ed from the standalone test bundle. The *decision* logic it now delegates to is unit-tested in Task 4 (`ShareSaveFlowTests`); the *persistence* path it drives (decode → create → attach) is already covered end-to-end by `ShareExtensionPayloadTests`. This task wires `save()` to `ShareSaveFlow` and stops swallowing the attachment error; correctness of the new wiring is verified by the build plus those existing suites.

- [ ] **Step 1: Add the saved-task-ID state.** In `ShareRootView.swift`, replace the `@State` block (lines 13–17) with one that adds `savedTaskID`:

```swift
    @State private var title = ""
    @State private var notes = ""
    @State private var attachedURL: URL?
    @State private var saving = false
    @State private var saveError: String?
    /// Set once the task is successfully created. On a retry after a
    /// failed link attachment we reuse this instead of creating a second
    /// task (see `ShareSaveFlow`).
    @State private var savedTaskID: UUID?
```

- [ ] **Step 2: Rewrite `save()` to propagate the attachment failure and reuse the saved task on retry.** Replace the `save()` method (lines 63–98) with:

```swift
    private func save() async {
        saving = true
        defer { saving = false }
        saveError = nil
        do {
            // Plan 21: consult MigrationGate so the extension doesn't
            // race a foreground sync-mode migration. If a migration is
            // in flight, surface the message and let the user retry.
            let appGroupID = "group.io.mikeydotio.Lillist"
            let modeStore = SyncModeStore(appGroupID: appGroupID)
            guard let journal = FileMigrationJournalStore(appGroupID: appGroupID) else {
                saveError = "App Group container is not available."
                return
            }
            let gate = MigrationGate(journal: journal, modeStore: modeStore)
            let config = try await gate.resolveStoreConfiguration(appGroupID: appGroupID)
            let persistence = try await PersistenceController(configuration: config)
            let taskStore = TaskStore(persistence: persistence)
            let attachmentStore = AttachmentStore(persistence: persistence)

            // Decide create-vs-reuse. On a retry after a failed link
            // attachment the task already exists, so we must not create a
            // second one — only re-attempt the attachment.
            let taskID: UUID
            switch ShareSaveFlow.next(savedTaskID: savedTaskID, hasURL: attachedURL != nil) {
            case .createTask:
                taskID = try await taskStore.create(title: title, notes: notes)
                savedTaskID = taskID
            case .attachLinkOnly(let existing):
                taskID = existing
            }

            // Link attachment failures are no longer swallowed: surface
            // them and keep the sheet open so the user can retry. The task
            // is already saved, so a retry won't duplicate it.
            if let url = attachedURL {
                _ = try await attachmentStore.addLinkPreview(
                    taskID: taskID,
                    url: url,
                    title: nil,
                    description: nil,
                    thumbnailData: nil,
                    faviconData: nil
                )
            }
            onSaved()
        } catch let LillistError.storeUnavailable(reason) {
            saveError = reason
        } catch {
            saveError = "\(error)"
        }
    }
```

- [ ] **Step 3: Verify the extension target compiles and existing share tests still pass.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests/ShareExtensionPayloadTests \
    -only-testing:Lillist-iOSTests/SharePayloadTests \
    -only-testing:Lillist-iOSTests/ShareSaveFlowTests 2>&1 | tail -25
  ```
  Expected: `** TEST SUCCEEDED **` — `ShareRootView.swift` compiles with `ShareSaveFlow` in scope, and all three share suites remain green. No warnings (the previously-`try?`-discarded result is now `try` so there is no "result of call is unused" diagnostic change).

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShareExtension-iOS/ShareRootView.swift
  git commit -m "fix(ext): surface link-attachment failures in Share save, keep sheet open

ShareRootView.save() no longer swallows addLinkPreview errors with try?.
A failed attachment now lands in saveError with the sheet still open, and
on retry the flow reuses the already-created task (via ShareSaveFlow)
instead of spawning a duplicate. Closes ext-4."
  ```

---

## Task 6: Integration test for the bounded suggestions fetch (ext-3)

**Files:**
- Create: `Apps/Lillist-iOS/Tests/IntegrationTests/SuggestedEntitiesLimitTests.swift`.

`TaskEntityQuery.suggestedEntities()` lives in the unimportable extension target, but the LillistCore path it now depends on — `SmartFilterStore.evaluate(group:limit:)` with the exact predicate `suggestedEntities` builds — is fully reachable from the standalone test bundle. This integration test pins the end-to-end behavior the intent relies on: with >20 open tasks, the limited evaluate returns exactly 20.

- [ ] **Step 1: Write the failing test.** Create `Apps/Lillist-iOS/Tests/IntegrationTests/SuggestedEntitiesLimitTests.swift`:

```swift
import XCTest
import Foundation
import LillistCore

/// Mirrors the LillistCore path `TaskEntityQuery.suggestedEntities()` takes:
/// the same "not-trashed, not-closed" predicate group evaluated with a
/// limit of 20. The intent itself can't be `@testable import`-ed from this
/// standalone bundle, so we exercise the shared store call directly and
/// pin the bound that Shortcuts depends on.
final class SuggestedEntitiesLimitTests: XCTestCase {
    func test_suggestions_predicate_with_limit_returns_at_most_twenty() async throws {
        let persistence = try await PersistenceController(configuration: .inMemory)
        let taskStore = TaskStore(persistence: persistence)
        let filters = SmartFilterStore(persistence: persistence)

        for i in 0..<30 {
            _ = try await taskStore.create(title: "Open task \(i)")
        }

        let recent = PredicateGroup(
            combinator: .all,
            predicates: [
                .leaf(Leaf(field: .inTrash, op: .is, value: .bool(false))),
                .leaf(Leaf(field: .status, op: .isNot, value: .statusSet([.closed])))
            ]
        )

        let suggested = try await filters.evaluate(
            group: recent,
            sort: .modifiedAt,
            ascending: false,
            limit: 20
        )
        XCTAssertEqual(suggested.count, 20, "suggestedEntities must cap at 20 rows")
    }
}
```

- [ ] **Step 2: Run the test, expect failure (then pass after Task 1).** If Task 1 is not yet merged into the working tree, this fails to compile with `error: argument 'limit' must precede argument 'group'` / `extra argument 'limit' in call`. Run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests/SuggestedEntitiesLimitTests 2>&1 | tail -25
  ```
  Expected (Task 1 already merged, which it must be for this plan's ordering): the test runs and **passes** — `** TEST SUCCEEDED **`, `test_suggestions_predicate_with_limit_returns_at_most_twenty` green. (This is a regression guard for the bound, not a fresh red — Task 1 already proved the `limit` parameter at the unit level; this proves the exact `suggestedEntities` predicate + limit combination at the integration level.)

- [ ] **Step 3: Regenerate pbxproj (new test file) and confirm it is picked up.** The new file sits under `Tests/IntegrationTests`, which is already a `sources` path, so no `project.yml` edit is needed — but the pbxproj must be regenerated to enumerate the new file:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .
  ```
  Re-run Step 2's command and confirm `SuggestedEntitiesLimitTests` appears in the run summary.

- [ ] **Step 4: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Apps/Lillist-iOS/Tests/IntegrationTests/SuggestedEntitiesLimitTests.swift \
          Apps/Lillist-iOS/Lillist-iOS.xcodeproj
  git commit -m "test(ext): pin suggestedEntities to a 20-row bound

Integration test exercising the exact not-trashed/not-closed predicate
group that TaskEntityQuery.suggestedEntities() builds, evaluated with
limit: 20, asserting the cap holds against 30 open tasks. Guards ext-3
end-to-end."
  ```

---

## Task 7: Resolve the dead helper-intent surface (ext-5)

**Files:**
- Modify: `Extensions/ShortcutsActions/OpenTaskIntent.swift` (whole file, currently lines 1–35).
- Modify: `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift` (whole file, currently lines 1–27).

Evidence (`ext-5`): `OpenTaskInAppIntent` and `OpenAtQuickCaptureIntent` are `isDiscoverable = false` helper intents whose `perform()` bodies do nothing but `return .result()`. A repo-wide search confirms **nothing in either app target handles them** (`grep -rn "OpenTaskInAppIntent\|OpenAtQuickCaptureIntent" Apps/` returns no handler) — they are pure no-ops. The honest, YAGNI-correct fix is to remove the dead indirection and collapse each public intent to the single `openAppWhenRun = true` behavior it actually delivers (just open the app). Building genuine deep-link handling would require an entirely new app-side AppIntents surface that does not exist and is out of this plan's scope.

> No unit test: these intents are AppIntent types in the unimportable signed extension target, and the only behavior left after removing the dead helpers is the framework's own `openAppWhenRun`. Verification is the build plus confirming the deleted symbols have no remaining references.

- [ ] **Step 1: Collapse `OpenTaskIntent`.** Replace the entire contents of `Extensions/ShortcutsActions/OpenTaskIntent.swift` with:

```swift
import AppIntents

/// Opens Lillist with a chosen task. The app currently has no AppIntents
/// deep-link surface to scroll to a specific task, so this intent's only
/// effect is to bring the app to the foreground (`openAppWhenRun`). The
/// task parameter is retained so the Shortcuts UI still lets the user pick
/// a task and so the surface is ready when in-app navigation lands.
struct OpenTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Task"
    static let description = IntentDescription("Open a task in Lillist.")
    static let openAppWhenRun = true

    @Parameter(title: "Task") var task: TaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$task)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
```

- [ ] **Step 2: Collapse `QuickCaptureLockScreenIntent`.** Replace the entire contents of `Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift` with:

```swift
import AppIntents

/// Discoverable entry point used by the Lock Screen widget and Shortcuts.
/// Brings Lillist to the foreground (`openAppWhenRun`); the app has no
/// AppIntents surface to auto-present the Quick Capture sheet, so this
/// intent's effect today is simply to open the app.
struct QuickCaptureLockScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Capture"
    static let description = IntentDescription("Capture a task into Lillist.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}
```

- [ ] **Step 3: Confirm no dangling references to the removed helpers.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -rn "OpenTaskInAppIntent\|OpenAtQuickCaptureIntent" --include="*.swift" Apps/ Extensions/
  ```
  Expected: no output (both helper symbols are fully removed; the only prior references were inside the two files just rewritten and in their doc comments).

- [ ] **Step 4: Verify the extension target compiles.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -20
  ```
  Expected: `** BUILD SUCCEEDED **`. `LillistShortcuts.swift` still references `QuickCaptureLockScreenIntent()` (unchanged type name) and compiles cleanly. No "unused" or unresolved-symbol warnings from the removed helper intents.

- [ ] **Step 5: Commit.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist
  git add Extensions/ShortcutsActions/OpenTaskIntent.swift \
          Extensions/ShortcutsActions/QuickCaptureLockScreenIntent.swift
  git commit -m "refactor(ext): remove dead open-app helper intents

OpenTaskInAppIntent and OpenAtQuickCaptureIntent were no-op indirection
intents (isDiscoverable=false, perform() returned .result() with nothing
in either app handling them). Collapsed OpenTaskIntent and
QuickCaptureLockScreenIntent to the single openAppWhenRun behavior they
actually deliver, removing the dead surface. Closes ext-5."
  ```

---

## Task 8: Full regression sweep across all touched targets

**Files:** none (verification only).

- [ ] **Step 1: LillistCore package tests.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -15
  ```
  Expected: all tests pass (including the new `evaluateRespectsLimit`), zero warnings.

- [ ] **Step 2: Verify the pbxproj is in sync (no xcodegen drift).**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project . \
    && cd /Volumes/Code/mikeyward/Lillist && git diff --exit-code Apps/Lillist-iOS/Lillist-iOS.xcodeproj
  ```
  Expected: `xcodegen` reports success and `git diff --exit-code` produces no output and exit code 0 (the committed pbxproj already matches a fresh generation).

- [ ] **Step 3: Full iOS test bundle.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:Lillist-iOSTests 2>&1 | tail -25
  ```
  Expected: `** TEST SUCCEEDED **` with `ShareSaveFlowTests`, `SuggestedEntitiesLimitTests`, `ShareExtensionPayloadTests`, `SharePayloadTests`, and `AppIntentHandlerTests` all green.

- [ ] **Step 4: Confirm warnings-as-errors build of the app + extensions.**
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -10
  ```
  Expected: `** BUILD SUCCEEDED **`, no warnings anywhere in `ShortcutsActions` or `ShareExtension-iOS`.

> No commit in this task — it is a verification gate. If anything is red, fix it under the owning task before considering the plan complete.

---

## Self-review checklist

- [ ] **ext-1** — `TaskEntityQuery` no longer has its own ungated `makePersistence()`; both `entities(for:)` and `suggestedEntities()` route through `IntentSupport.makePersistence()` (gated, syncMode-honouring, `storeUnavailable`-propagating). **Covered by Task 3** (build-verified; the gated factory is shared with the already-tested `AppIntentHandlerTests` path).
- [ ] **ext-2** — `IntentSupport.makePersistence()` caches one per-process `PersistenceController` keyed on the gate-resolved `StoreConfiguration`, rebuilding only when the configuration changes; the gate is still consulted every call. **Covered by Task 2.**
- [ ] **ext-3** — `SmartFilterStore.evaluate(group:…)` gains a `limit` parameter applied as `fetchLimit`; `suggestedEntities()` calls it with `limit: 20` instead of fetching everything and slicing. **Covered by Task 1** (unit), **Task 3** (wiring), and **Task 6** (integration bound).
- [ ] **ext-4** — `ShareRootView.save()` propagates link-attachment failure into `saveError`, keeps the sheet open, and reuses the already-created task on retry (via `ShareSaveFlow`) instead of creating a duplicate. **Covered by Task 4** (helper + retry-semantics tests) and **Task 5** (wiring).
- [ ] **ext-5** — The dead no-op helper intents `OpenTaskInAppIntent` and `OpenAtQuickCaptureIntent` are removed; `OpenTaskIntent` and `QuickCaptureLockScreenIntent` are collapsed to their single real `openAppWhenRun` behavior. **Covered by Task 7.**
- [ ] **ext-6** — The divergent Share decision logic is extracted into the pure `ShareSaveFlow` helper, co-compiled into the standalone iOS test bundle via `project.yml` `sources`, and unit-tested. **Covered by Task 4.**

### Strengths preserved (per the review's "do not refactor away")
- The **gated extension persistence path** (`IntentSupport.makePersistence()` consulting `MigrationGate`) is reinforced, not removed — `TaskEntityQuery` now joins it.
- The **DTO boundary** is untouched: `TaskEntity` is still built from `TaskStore.TaskRecord`; no `NSManagedObject` crosses the boundary.
- The **standalone-test-bundle / co-compiled-source pattern** (`SharePayload.swift`, `ReportCrashIntent.swift`) is extended consistently (`ShareSaveFlow.swift`), not replaced.
- **Swift Testing for LillistCore, XCTest for the iOS app bundle** — each new test matches its directory's existing framework.
