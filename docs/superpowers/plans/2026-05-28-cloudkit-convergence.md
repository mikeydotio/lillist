# CloudKit Cross-Device Convergence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make multi-device CloudKit sync converge deterministically — stop `AppPreferences` from flip-flopping across devices, drive notification reconciliation from remote imports, attribute view-context writes for history diffing, enforce one default spec per `(taskID, kind)`, and give steady-state `CKError` quota/rate-limit a real error posture.

**Architecture:** A well-known constant `AppPreferences.id` plus a one-time idempotent normalization pass collapses the random-UUID singletons CloudKit currently duplicates. A new `RemoteChangeReconciler` reads `NSPersistentHistoryTransaction`s after each `NSPersistentStoreRemoteChange`, diffs which `NotificationSpec.lastFiredAt` values an *import* changed, and enqueues `reconcile(taskID:)` so non-firing devices drop their stale pending requests. `viewContext.transactionAuthor`/`.name` are set at store load so local writes are distinguishable from CloudKit imports in the history stream. `NotificationSpecStore.add` gains an at-most-one-default-per-kind guard. `CKError` quota/rate-limit is classified into the existing `LillistError` taxonomy and the store-wide `mergeByPropertyObjectTrump` policy is documented (kept, with a recorded rationale) rather than silently inherited.

**Tech Stack:** Swift 6.2, Core Data (`NSPersistentCloudKitContainer`), `NSPersistentHistoryChangeRequest` / `NSPersistentHistoryTransaction` / `NSPersistentHistoryToken`, CloudKit (`CKError`), Swift Testing (`import Testing`, `@Test`/`#expect`).

**Source findings:** `persist-2`, `conc-3`, `notif-2`, `persist-5` (review §92, blind-spot §6).

---

## File Structure

### Create

| Path | Responsibility |
|------|----------------|
| `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift` | Observes `NSPersistentStoreRemoteChange`, walks `NSPersistentHistoryTransaction`s from the last seen token, and reports which `taskID`s had a `NotificationSpec.lastFiredAt` changed by an import; persists the history token between launches. |
| `Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift` | Tiny `UserDefaults`-backed persistence for the last-processed `NSPersistentHistoryToken` (App-Group aware), so a relaunch resumes diffing from where it left off instead of replaying the whole store. |
| `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift` | Pure mapping from a raw `Error`/`CKError` to a `LillistError` (`quotaExceeded`, `syncFailure` for rate-limit/server-rejected), so steady-state CloudKit failures get a typed, surfaceable posture. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PreferencesStoreSingletonTests.swift` | Stable-UUID + normalization convergence tests for `PreferencesStore`. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift` | History-token diffing tests: import-driven `lastFiredAt` change enqueues the right `taskID`; local writes do not. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistentHistoryTokenStoreTests.swift` | Round-trip + reset tests for the token store. |
| `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitErrorClassifierTests.swift` | `CKError` → `LillistError` mapping tests. |

### Modify

| Path | Responsibility / Change |
|------|--------------------------|
| `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift` (`fetchOrCreateSingleton`, lines 174–197; add a `normalizeSingletons` pass) | Use a well-known constant `id`; collapse pre-existing random-UUID rows into one. |
| `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift` (`init`, lines 43–46) | Set `viewContext.transactionAuthor` and `viewContext.name` after store load. |
| `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift` (`add`, lines 33–57) | Enforce at-most-one `defaultStart`/`defaultDeadline` per `(taskID, kind)`: return the existing default's id instead of inserting a duplicate. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift` (append) | Assert `transactionAuthor`/`name` are set; assert the kept merge-policy rationale. |
| `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift` (append) | Assert duplicate default `add` is idempotent. |
| `docs/engineering-notes.md` (append one entry) | Record the well-known-UUID singleton rule, the transaction-author convention, the kept merge-policy rationale, and the history-token diffing pattern. |

---

## Task 1: Set a stable transaction author + name on the view context (conc-3)

History-token diffing in Task 4 can only tell *local* writes from *CloudKit imports* if local writes carry a `transactionAuthor`. CloudKit's mirror uses the reserved author `NSCloudKitMirroringDelegate.import` for imports; setting our own author on `viewContext` lets the reconciler ignore our own transactions.

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift` (lines 43–46)
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift` (append)

- [ ] **Step 1: Write the failing test** — append to `PersistenceControllerCloudKitTests.swift`, inside the existing `struct PersistenceControllerCloudKitTests { ... }` (before the closing `}` on line 109):

```swift
    @Test("viewContext carries a stable transaction author + name after store load")
    func viewContextTransactionAuthorIsSet() async throws {
        let controller = try await PersistenceController(configuration: .inMemory)
        #expect(controller.container.viewContext.transactionAuthor == PersistenceController.localTransactionAuthor)
        #expect(controller.container.viewContext.name == PersistenceController.localTransactionAuthor)
    }
```

- [ ] **Step 2: Run the test, expect failure** — 
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PersistenceControllerCloudKitTests
```
Expected: compile error `type 'PersistenceController' has no member 'localTransactionAuthor'`.

- [ ] **Step 3: Implement the minimal change** — in `PersistenceController.swift`, add the constant just under `public let cloudKitEventBridge: CloudKitEventBridge` (line 25) and a comment, then set the author/name in `init`. Replace lines 43–46:

```swift
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
```

with:

```swift
        container.viewContext.automaticallyMergesChangesFromParent = true
        // Store-wide conflict policy. `mergeByPropertyObjectTrump` keeps the
        // *in-memory* (just-written) value when a CloudKit import collides on a
        // property — last-writer-on-this-device wins per attribute. This is the
        // pragmatic default for a single-user multi-device account: edits made
        // here while offline survive a re-pull. The known cost (review persist-5)
        // is that a *concurrent edit on another device* to the same property is
        // silently discarded on merge; per-record field-level CRDT reconciliation
        // is out of scope (YAGNI) until a real conflict report appears. Documented
        // in engineering-notes.md so the choice is explicit, not inherited.
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        // Attribute every write made through `viewContext` so the persistent-history
        // stream can distinguish our own local transactions from CloudKit imports
        // (whose author is the reserved `NSCloudKitMirroringDelegate.import`).
        // `RemoteChangeReconciler` keys off this author to skip self-originated
        // history when deciding which tasks to reconcile after a remote pull.
        container.viewContext.transactionAuthor = Self.localTransactionAuthor
        container.viewContext.name = Self.localTransactionAuthor
```

Then add the constant under line 25 (`public let cloudKitEventBridge: CloudKitEventBridge`):

```swift

    /// Transaction author stamped on every `viewContext` write. Lets the
    /// persistent-history diff in `RemoteChangeReconciler` ignore
    /// self-originated transactions and react only to CloudKit imports
    /// (which carry Core Data's reserved import author). Value is an opaque
    /// stable string, not the device fingerprint — per-device identity isn't
    /// needed here, only "this app vs. the CloudKit mirror".
    public static let localTransactionAuthor = "Lillist.app"
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PersistenceControllerCloudKitTests
```
Expected: `Test viewContextTransactionAuthorIsSet ... passed` and all sibling CloudKit tests still pass (e.g. `mergePolicyPreserved`).

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceControllerCloudKitTests.swift && git commit -m "feat(persistence): stamp a stable transaction author on viewContext

Sets viewContext.transactionAuthor/.name to a constant so the
persistent-history diff can separate local writes from CloudKit
imports. Documents the kept mergeByPropertyObjectTrump rationale
inline (conc-3, persist-5 part 1)."
```

---

## Task 2: Give AppPreferences a well-known UUID + one-time normalization (persist-2)

`fetchOrCreateSingleton` assigns `row.id = UUID()` (line 181) — a *different* random id on every device. CloudKit sees two distinct records and keeps both, so each device's "singleton" preference row fights the other's. Fix: a constant id so both devices materialize the *same* CloudKit record, plus a normalization pass that collapses any pre-existing random-UUID rows (the realistic upgrade case) into one canonical row.

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift` (lines 174–197)
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PreferencesStoreSingletonTests.swift` (create)

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PreferencesStoreSingletonTests.swift`:

```swift
import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("PreferencesStore singleton convergence")
struct PreferencesStoreSingletonTests {
    @Test("Freshly-created singleton uses the well-known constant id")
    func freshSingletonUsesWellKnownID() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        // Force materialization.
        _ = try await prefs.read()

        let id = try await p.container.viewContext.perform {
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            return try p.container.viewContext.fetch(req).first?.id
        }
        #expect(id == PreferencesStore.singletonID)
    }

    @Test("normalizeSingletons collapses duplicate random-UUID rows into one canonical row")
    func normalizeCollapsesDuplicates() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext

        // Simulate two devices having each created their own random-UUID row
        // (the pre-fix cross-device duplication bug). Give the row we want to
        // survive a distinguishing field value.
        try await ctx.perform {
            let a = AppPreferences(context: ctx)
            a.id = UUID()
            a.trashRetentionDays = 30
            a.morningSummaryHour = 7   // canary: the newest write wins
            let b = AppPreferences(context: ctx)
            b.id = UUID()
            b.trashRetentionDays = 30
            b.morningSummaryHour = 9
            try ctx.save()
        }

        let prefs = PreferencesStore(persistence: p)
        try await prefs.normalizeSingletons()

        let (count, survivingID, hour) = try await ctx.perform { () -> (Int, UUID?, Int16) in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            let rows = try ctx.fetch(req)
            return (rows.count, rows.first?.id, rows.first?.morningSummaryHour ?? -1)
        }
        #expect(count == 1)
        #expect(survivingID == PreferencesStore.singletonID)
        // The canonical row retains a coherent value (not a torn merge); the
        // contract is "one row, well-known id", field-value tie-break is
        // documented to pick the row that sorts first deterministically.
        #expect(hour == 7 || hour == 9)
    }

    @Test("normalizeSingletons is idempotent and a no-op on a clean store")
    func normalizeIdempotent() async throws {
        let p = try await TestStore.make()
        let prefs = PreferencesStore(persistence: p)
        _ = try await prefs.read()                 // creates one canonical row
        try await prefs.normalizeSingletons()      // first pass: nothing to do
        try await prefs.normalizeSingletons()      // second pass: still nothing
        #expect(try await prefs.rowCount() == 1)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PreferencesStoreSingletonTests
```
Expected: compile error `type 'PreferencesStore' has no member 'singletonID'` (and `normalizeSingletons`).

- [ ] **Step 3: Implement the minimal change** — in `PreferencesStore.swift`, add the constant and the normalization method, and change `fetchOrCreateSingleton` to use the constant id. First, add the constant just under the class opening (after line 4, `public final class PreferencesStore: @unchecked Sendable {`):

```swift
    /// Well-known, stable identity for the single `AppPreferences` row.
    ///
    /// Before this, `fetchOrCreateSingleton` minted a fresh `UUID()` on every
    /// device, so CloudKit mirrored *two distinct records* for the "singleton"
    /// and the two devices' preferences flip-flopped (review persist-2). Using
    /// one constant id means both devices converge on the same CloudKit record;
    /// `mergeByPropertyObjectTrump` then reconciles property-by-property instead
    /// of duplicating the whole row. The value is a fixed UUID literal — never
    /// regenerate it; existing stores depend on it.
    public static let singletonID = UUID(uuidString: "5111A570-0000-4000-8000-000000000001")!
```

Next, replace `fetchOrCreateSingleton` (lines 174–197) with:

```swift
    private func fetchOrCreateSingleton(in ctx: NSManagedObjectContext) throws -> AppPreferences {
        // Prefer the canonical well-known-id row. Falling back to "any row"
        // keeps a legacy random-UUID store readable until `normalizeSingletons`
        // collapses it (called once at bootstrap).
        let canonical = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        canonical.predicate = NSPredicate(format: "id == %@", Self.singletonID as CVarArg)
        canonical.fetchLimit = 1
        if let existing = try ctx.fetch(canonical).first {
            return existing
        }
        let anyReq = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
        anyReq.fetchLimit = 1
        if let legacy = try ctx.fetch(anyReq).first {
            // Adopt the legacy row's identity in place so we don't strand a
            // CloudKit record; `normalizeSingletons` handles the multi-row case.
            legacy.id = Self.singletonID
            try ctx.save()
            return legacy
        }
        let row = AppPreferences(context: ctx)
        row.id = Self.singletonID
        row.defaultAllDayNotificationHour = 9
        row.defaultAllDayNotificationMinute = 0
        row.morningSummaryEnabled = true
        row.morningSummaryHour = 9
        row.morningSummaryMinute = 0
        row.trashRetentionDays = 30
        row.defaultTaskListSortRaw = SortField.manualPosition.rawValue
        row.crashPromptsEnabled = true
        row.hasCompletedOnboarding = false
        row.quickCaptureEnabled = true
        row.quickCaptureHotkey = "ctrl+opt+space"
        row.statusBarItemVisible = true
        row.defaultTagTintHex = "#7F8FA6"
        try ctx.save()
        return row
    }

    /// One-time-per-launch convergence pass: collapse every `AppPreferences`
    /// row down to a single canonical row carrying `singletonID`.
    ///
    /// Pre-fix stores (and any device that synced before this fix shipped) can
    /// hold multiple random-UUID rows. We keep the row that sorts first by id
    /// (deterministic across devices), reassign it `singletonID`, and delete the
    /// rest. Idempotent: on an already-canonical store this fetches one row and
    /// returns without writing. Safe to call on every bootstrap.
    public func normalizeSingletons() async throws {
        try await context.perform { [self] in
            let req = NSFetchRequest<AppPreferences>(entityName: "AppPreferences")
            req.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
            let rows = try context.fetch(req)
            guard let survivor = rows.first else { return }       // empty store
            if rows.count == 1 && survivor.id == Self.singletonID {
                return                                            // already canonical
            }
            survivor.id = Self.singletonID
            for extra in rows.dropFirst() {
                context.delete(extra)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PreferencesStoreSingletonTests
```
Expected: all three tests pass. Also run the existing preference tests to confirm no regression:
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter AppPreferencesPartitionMigratorTests
```
Expected: both `AppPreferencesPartitionMigratorTests` still pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PreferencesStoreSingletonTests.swift && git commit -m "fix(preferences): converge AppPreferences on a well-known singleton UUID

Replaces the per-device random UUID with a fixed constant so CloudKit
mirrors one shared record instead of duplicating the singleton across
devices, and adds an idempotent normalizeSingletons() pass to collapse
legacy multi-row stores (persist-2)."
```

---

## Task 3: Enforce at-most-one default spec per (taskID, kind) (notif-2)

`NotificationSpecStore.add` unconditionally inserts. A concurrent reconcile (two devices, or two overlapping `reconcile(taskID:)` cycles) can each call `materializeDefaultSpecs` and create a *second* `.defaultStart`/`.defaultDeadline`. The store is the single seam every path funnels through, so the invariant belongs here: for the two *default* kinds, return the existing spec's id instead of inserting a duplicate. Offset/nudge kinds are intentionally multi-instance and unaffected.

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift` (lines 33–57)
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift` (append)

- [ ] **Step 1: Write the failing test** — append to `NotificationSpecStoreTests.swift`, inside the existing `struct NotificationSpecStoreTests { ... }` (before its closing `}` on line 89):

```swift
    @Test("add is idempotent for default kinds: a second defaultStart returns the same spec")
    func addDefaultIsIdempotent() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let first = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        let second = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        #expect(first == second)

        let all = try await specs.specs(forTask: taskID)
        let defaultStarts = all.filter { $0.kind == .defaultStart }
        #expect(defaultStarts.count == 1)
    }

    @Test("Concurrent default adds still yield exactly one defaultDeadline spec")
    func concurrentDefaultAddsConverge() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    _ = try? await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
                }
            }
        }

        let all = try await specs.specs(forTask: taskID)
        let defaults = all.filter { $0.kind == .defaultDeadline }
        #expect(defaults.count == 1)
    }

    @Test("Offset kinds remain multi-instance (the guard is default-only)")
    func offsetKindsRemainMultiInstance() async throws {
        let p = try await TestStore.make()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let a = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -15, fireDate: nil)
        let b = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -30, fireDate: nil)
        #expect(a != b)
        let offsets = try await specs.specs(forTask: taskID).filter { $0.kind == .offsetStart }
        #expect(offsets.count == 2)
    }
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationSpecStoreTests
```
Expected: `addDefaultIsIdempotent` fails with `Expectation failed: (defaultStarts.count → 2) == 1` (and `concurrentDefaultAddsConverge` failing with a count > 1).

- [ ] **Step 3: Implement the minimal change** — in `NotificationSpecStore.swift`, replace `add` (lines 33–57) with:

```swift
    @discardableResult
    public func add(
        taskID: UUID,
        kind: NotificationKind,
        offsetMinutes: Int32?,
        fireDate: Date?
    ) async throws -> UUID {
        try await context.perform { [self] in
            let task = try fetchTask(id: taskID, in: context)
            // Default specs are singletons per (task, kind): exactly one
            // .defaultStart and one .defaultDeadline may exist for a task.
            // Two overlapping reconcile cycles (or two devices) can each try
            // to materialize the default; without this guard they'd create a
            // duplicate that the scheduler would then de-dup at the OS level
            // only by accident. Returning the existing id keeps `add`
            // idempotent for defaults while leaving offset/nudge multi-instance
            // (review notif-2). The dedup is scoped to this task's specs via the
            // `task == %@` predicate, not a model-level unique constraint, so it
            // composes with CloudKit (which doesn't honor uniqueness constraints).
            if kind == .defaultStart || kind == .defaultDeadline {
                let existing = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
                existing.predicate = NSPredicate(format: "task == %@ AND kindRaw == %d", task, kind.rawValue)
                existing.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                let found = try context.fetch(existing)
                if let survivor = found.first {
                    // Collapse any duplicates a previous race already created so
                    // the store self-heals on the next add (CloudKit imports
                    // can deliver a second default before this guard ran).
                    for dup in found.dropFirst() {
                        context.delete(dup)
                    }
                    if context.hasChanges { try context.save() }
                    return survivor.id ?? UUID()
                }
            }
            let spec = NotificationSpec(context: context)
            let id = UUID()
            spec.id = id
            spec.task = task
            spec.kind = kind
            if let offsetMinutes {
                spec.offsetMinutes = NSNumber(value: offsetMinutes)
            } else {
                spec.offsetMinutes = nil
            }
            spec.fireDate = fireDate
            spec.createdAt = Date()
            try context.save()
            return id
        }
    }
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationSpecStoreTests
```
Expected: all tests in the suite pass, including the new three. Then run the scheduler layer suites to confirm reconciliation still behaves:
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter NotificationScheduler
```
Expected: all `NotificationScheduler*` suites pass (Layer1/2/3/4, DST, CrossDeviceDedup, Snooze, StatusTransitions, PreferenceChange, Nudge).

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Notifications/NotificationSpecStore.swift Packages/LillistCore/Tests/LillistCoreTests/Notifications/NotificationSpecStoreTests.swift && git commit -m "fix(notifications): enforce one default spec per (task, kind)

NotificationSpecStore.add now returns the existing default spec id for
.defaultStart/.defaultDeadline instead of inserting a duplicate, and
self-heals any duplicates a prior race or CloudKit import created.
Offset/nudge kinds stay multi-instance (notif-2)."
```

---

## Task 4: Persistent-history token store (foundation for the remote-change reconciler)

The reconciler in Task 5 needs to replay history *since the last transaction it saw* (not the whole store) and survive relaunches. A small `UserDefaults`-backed token store handles that. Tokens are archived via `NSKeyedArchiver` (the public, documented way to persist an `NSPersistentHistoryToken`).

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistentHistoryTokenStoreTests.swift`

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistentHistoryTokenStoreTests.swift`:

```swift
import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("PersistentHistoryTokenStore")
struct PersistentHistoryTokenStoreTests {
    private static func freshSuiteName() -> String {
        let suite = "PersistentHistoryTokenStoreTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        return suite
    }

    @Test("No token persisted on a fresh store")
    func freshStoreHasNoToken() {
        let store = PersistentHistoryTokenStore(suiteName: Self.freshSuiteName())
        #expect(store.lastToken == nil)
    }

    @Test("A token round-trips through archive/unarchive")
    func tokenRoundTrips() async throws {
        // Drive a real write so Core Data hands us a genuine history token.
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "T"
            try ctx.save()
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            let txns = result?.result as? [NSPersistentHistoryTransaction]
            return txns?.last?.token
        }
        let real = try #require(token)

        let suite = Self.freshSuiteName()
        let a = PersistentHistoryTokenStore(suiteName: suite)
        a.lastToken = real
        let b = PersistentHistoryTokenStore(suiteName: suite)
        #expect(b.lastToken == real)
    }

    @Test("Setting nil clears the persisted token")
    func clearingToken() async throws {
        let p = try await TestStore.make()
        let ctx = p.container.viewContext
        let token: NSPersistentHistoryToken? = try await ctx.perform {
            let t = LillistTask(context: ctx)
            t.id = UUID()
            t.title = "T"
            try ctx.save()
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil)
            let result = try ctx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }
        let suite = Self.freshSuiteName()
        let store = PersistentHistoryTokenStore(suiteName: suite)
        store.lastToken = token
        store.lastToken = nil
        let reopened = PersistentHistoryTokenStore(suiteName: suite)
        #expect(reopened.lastToken == nil)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PersistentHistoryTokenStoreTests
```
Expected: compile error `cannot find 'PersistentHistoryTokenStore' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift`:

```swift
import Foundation
import CoreData

/// Persists the last-processed `NSPersistentHistoryToken` so the
/// `RemoteChangeReconciler` resumes history diffing across launches instead
/// of replaying the whole store every time.
///
/// The token is archived with `NSKeyedArchiver` (the documented way to
/// persist an `NSPersistentHistoryToken`) into App-Group `UserDefaults`, so
/// the main app and its extensions share one watermark. `@unchecked Sendable`
/// because `UserDefaults` is internally thread-safe and the only mutable state
/// is delegated to it.
public final class PersistentHistoryTokenStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "com.mikeydotio.lillist.persistentHistoryToken"

    /// Backed by an explicit suite (tests) or the App Group (production).
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Backed by the App Group's shared defaults, falling back to `.standard`
    /// when the group container is unreachable (unsigned/test contexts).
    public init(appGroupID: String) {
        self.defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The last persistent-history token the reconciler has consumed, or `nil`
    /// if none has been recorded (fresh install / cleared).
    public var lastToken: NSPersistentHistoryToken? {
        get {
            guard let data = defaults.data(forKey: Self.key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        }
        set {
            guard let token = newValue else {
                defaults.removeObject(forKey: Self.key)
                return
            }
            if let data = try? NSKeyedArchiver.archivedData(
                withRootObject: token,
                requiringSecureCoding: true
            ) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PersistentHistoryTokenStoreTests
```
Expected: all three tests pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistentHistoryTokenStore.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistentHistoryTokenStoreTests.swift && git commit -m "feat(persistence): add PersistentHistoryTokenStore

App-Group-aware UserDefaults persistence for the last-processed
NSPersistentHistoryToken so the remote-change reconciler can resume
history diffing across launches (foundation for persist-2 convergence)."
```

---

## Task 5: RemoteChangeReconciler — diff history, enqueue reconcile(taskID:) on import (notif-2 + persist-2 convergence)

The single behavioral payload: when `NSPersistentStoreRemoteChange` fires, walk the persistent-history transactions since the last token, find changes to `NotificationSpec.lastFiredAt` that came from a *CloudKit import* (not our own author), collect the affected `taskID`s, advance the token, and hand the set to a callback (the app wires this to `scheduler.reconcile(taskID:)`). This is what makes a non-firing device drop its now-stale pending notification when another device records a fire.

Designed for testability: the diffing core is a `nonisolated` static pure function over an injected list of transactions, so tests don't need a live CloudKit container.

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift`

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift`:

```swift
import Testing
import CoreData
import Foundation
@testable import LillistCore

@Suite("RemoteChangeReconciler")
struct RemoteChangeReconcilerTests {
    /// Build the entity-name → ObjectID-class metadata the diffing core uses,
    /// straight off a real (in-memory) store so the test exercises the actual
    /// model, not a hand-rolled stand-in.
    private func makeContext() async throws -> (PersistenceController, NSManagedObjectContext) {
        let p = try await TestStore.make()
        return (p, p.container.viewContext)
    }

    @Test("A foreign-author lastFiredAt change yields the spec's taskID")
    func importChangeYieldsTaskID() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        // Resolve the spec's objectID + its task's objectID so we can hand the
        // diffing core a synthetic change record keyed on them.
        let (specObjectID, taskObjectID) = try await ctx.perform { () -> (NSManagedObjectID, NSManagedObjectID) in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try ctx.fetch(req).first!
            return (m.objectID, m.task!.objectID)
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["lastFiredAt"],
            author: "OtherDeviceImport"   // not our local author
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID])
        _ = taskObjectID
    }

    @Test("A self-authored change is ignored")
    func selfAuthoredChangeIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["lastFiredAt"],
            author: PersistenceController.localTransactionAuthor
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("A non-lastFiredAt property change on a spec is ignored")
    func unrelatedPropertyIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        let specID = try await specs.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        let specObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: specObjectID,
            entityName: "NotificationSpec",
            changedProperties: ["snoozedUntil"],   // not lastFiredAt
            author: "OtherDeviceImport"
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("A change to a non-NotificationSpec entity is ignored")
    func nonSpecEntityIgnored() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let taskID = try await tasks.create(title: "T")

        let taskObjectID = try await ctx.perform { () -> NSManagedObjectID in
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            return try ctx.fetch(req).first!.objectID
        }

        let change = RemoteChangeReconciler.SyntheticChange(
            changedObjectID: taskObjectID,
            entityName: "LillistTask",
            changedProperties: ["lastFiredAt"],
            author: "OtherDeviceImport"
        )

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: [change],
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected.isEmpty)
    }

    @Test("Duplicate taskIDs across multiple specs collapse to a unique set")
    func deduplicatesTaskIDs() async throws {
        let (p, ctx) = try await makeContext()
        let tasks = TaskStore(persistence: p)
        let specs = NotificationSpecStore(persistence: p)
        let taskID = try await tasks.create(title: "T")
        // Two distinct specs on the same task (one default, one offset).
        let s1 = try await specs.add(taskID: taskID, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        let s2 = try await specs.add(taskID: taskID, kind: .offsetStart, offsetMinutes: -10, fireDate: nil)

        let ids = try await ctx.perform { () -> [NSManagedObjectID] in
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id IN %@", [s1, s2])
            return try ctx.fetch(req).map(\.objectID)
        }
        let changes = ids.map {
            RemoteChangeReconciler.SyntheticChange(
                changedObjectID: $0,
                entityName: "NotificationSpec",
                changedProperties: ["lastFiredAt"],
                author: "OtherDeviceImport"
            )
        }

        let affected = try await RemoteChangeReconciler.affectedTaskIDs(
            from: changes,
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )
        #expect(affected == [taskID])
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RemoteChangeReconcilerTests
```
Expected: compile error `cannot find 'RemoteChangeReconciler' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift`:

```swift
import Foundation
import CoreData

/// Reacts to `NSPersistentStoreRemoteChange` notifications by diffing the
/// persistent-history stream and enqueuing notification reconciliation for the
/// tasks whose `NotificationSpec.lastFiredAt` a *CloudKit import* changed.
///
/// Why this exists (review notif-2, persist-2 §92): when device A delivers a
/// notification it writes `lastFiredAt`. Device B only learns of that fire via
/// CloudKit; without a remote-change-driven reconcile, B keeps its now-stale
/// pending request and the user gets a duplicate. This reconciler closes that
/// loop. It deliberately ignores self-authored transactions (matched against
/// `PersistenceController.localTransactionAuthor`) so an app's own writes don't
/// trigger a redundant reconcile cycle.
///
/// `@unchecked Sendable`: the only mutable state (the observer token and the
/// token watermark) is touched on the main actor in `start()`/`stop()` and the
/// token store is itself thread-safe.
public final class RemoteChangeReconciler: @unchecked Sendable {
    /// A flattened, Sendable view of one persistent-history change — either
    /// extracted from a real `NSPersistentHistoryChange` or constructed by a
    /// test. Keeps the diffing core pure and container-free.
    public struct SyntheticChange: Sendable {
        public let changedObjectID: NSManagedObjectID
        public let entityName: String
        public let changedProperties: Set<String>
        public let author: String?

        public init(
            changedObjectID: NSManagedObjectID,
            entityName: String,
            changedProperties: Set<String>,
            author: String?
        ) {
            self.changedObjectID = changedObjectID
            self.entityName = entityName
            self.changedProperties = changedProperties
            self.author = author
        }
    }

    private let persistence: PersistenceController
    private let tokenStore: PersistentHistoryTokenStore
    private let onAffectedTasks: @Sendable ([UUID]) async -> Void
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - persistence: the live controller (its `viewContext` is used to fetch
    ///     history and resolve `NotificationSpec` → `taskID`).
    ///   - tokenStore: watermark persistence so diffing resumes across launches.
    ///   - onAffectedTasks: callback invoked with the unique affected task ids.
    ///     The app wires this to `scheduler.reconcile(taskID:)` per id.
    public init(
        persistence: PersistenceController,
        tokenStore: PersistentHistoryTokenStore,
        onAffectedTasks: @escaping @Sendable ([UUID]) async -> Void
    ) {
        self.persistence = persistence
        self.tokenStore = tokenStore
        self.onAffectedTasks = onAffectedTasks
    }

    /// Begin observing `NSPersistentStoreRemoteChange`. Call once at bootstrap.
    public func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.processPendingHistory() }
        }
    }

    /// Stop observing. Optional in production (`[weak self]` makes a stale token
    /// a no-op), but lets tests/teardown be deterministic.
    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    deinit { stop() }

    /// Walk history since the last watermark, compute affected task ids, advance
    /// the watermark, and fire the callback. Public so the app can also call it
    /// once at launch (catch-up for changes that arrived while not running).
    public func processPendingHistory() async {
        let ctx = persistence.container.viewContext
        let after = tokenStore.lastToken
        let (changes, newToken): ([SyntheticChange], NSPersistentHistoryToken?)
        do {
            (changes, newToken) = try await ctx.perform { [weak self] in
                guard self != nil else { return ([], nil) }
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try ctx.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction]
                else { return ([], nil) }
                var flattened: [SyntheticChange] = []
                for txn in transactions {
                    for change in txn.changes ?? [] {
                        let name = change.changedObjectID.entity.name ?? ""
                        flattened.append(
                            SyntheticChange(
                                changedObjectID: change.changedObjectID,
                                entityName: name,
                                changedProperties: change.updatedProperties.map { Set($0.map(\.name)) } ?? [],
                                author: txn.author
                            )
                        )
                    }
                }
                return (flattened, transactions.last?.token)
            }
        } catch {
            return   // transient store error; next remote change retries
        }

        let affected = (try? await Self.affectedTaskIDs(
            from: changes,
            localAuthor: PersistenceController.localTransactionAuthor,
            in: ctx
        )) ?? []

        if let newToken {
            tokenStore.lastToken = newToken
        }
        if affected.isEmpty == false {
            await onAffectedTasks(affected)
        }
    }

    /// Pure-ish diffing core (no NotificationCenter, no live CloudKit): given a
    /// flat change list, return the de-duplicated, order-stable list of task ids
    /// whose `NotificationSpec.lastFiredAt` a foreign-author change touched.
    ///
    /// `nonisolated static` so XCTest / background callers can use it without
    /// crossing an actor boundary (CLAUDE.md UI-layer note generalizes here).
    public nonisolated static func affectedTaskIDs(
        from changes: [SyntheticChange],
        localAuthor: String,
        in ctx: NSManagedObjectContext
    ) async throws -> [UUID] {
        try await ctx.perform {
            var ordered: [UUID] = []
            var seen: Set<UUID> = []
            for change in changes {
                guard change.entityName == "NotificationSpec" else { continue }
                guard change.author != localAuthor else { continue }
                guard change.changedProperties.contains("lastFiredAt") else { continue }
                guard let spec = try? ctx.existingObject(with: change.changedObjectID) as? NotificationSpec
                else { continue }
                guard let taskID = spec.task?.id else { continue }
                if seen.insert(taskID).inserted {
                    ordered.append(taskID)
                }
            }
            return ordered
        }
    }
}
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter RemoteChangeReconcilerTests
```
Expected: all five tests pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/RemoteChangeReconciler.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift && git commit -m "feat(persistence): remote-change-driven notification reconcile

Adds RemoteChangeReconciler: on NSPersistentStoreRemoteChange it diffs
persistent history since the last token, finds NotificationSpec rows
whose lastFiredAt a CloudKit import changed, and enqueues reconcile for
those tasks so non-firing devices drop stale pending requests. Pure
diffing core is unit-tested without a live container (notif-2)."
```

---

## Task 6: CloudKit error classifier — typed posture for steady-state quota/rate-limit (persist-5)

A `LillistError.quotaExceeded` case exists but nothing maps a real `CKError` onto it. Steady-state CloudKit failures (`.quotaExceeded`, `.requestRateLimited`, `.serverRejectedRequest`, `.zoneBusy`) should classify into the existing taxonomy so the sync-status surface can show something actionable instead of an opaque `syncFailure`. The classifier is pure and unit-tested; wiring it into `CloudKitEventBridge.translate` is a one-line follow-up included here.

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift` (line 120, inside `translate`)
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitErrorClassifierTests.swift`

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitErrorClassifierTests.swift`:

```swift
import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("CloudKitErrorClassifier")
struct CloudKitErrorClassifierTests {
    private func ckError(_ code: CKError.Code) -> NSError {
        NSError(domain: CKErrorDomain, code: code.rawValue, userInfo: nil)
    }

    @Test("quotaExceeded maps to LillistError.quotaExceeded")
    func quota() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.quotaExceeded))
        #expect(mapped == .quotaExceeded(resource: "iCloud"))
    }

    @Test("requestRateLimited maps to a syncFailure mentioning rate limiting")
    func rateLimited() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.requestRateLimited))
        guard case let .syncFailure(underlying) = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
        #expect(underlying.localizedCaseInsensitiveContains("rate"))
    }

    @Test("serverRejectedRequest maps to a syncFailure")
    func serverRejected() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.serverRejectedRequest))
        guard case .syncFailure = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
    }

    @Test("zoneBusy maps to a syncFailure (transient/retryable)")
    func zoneBusy() {
        let mapped = CloudKitErrorClassifier.classify(ckError(.zoneBusy))
        guard case .syncFailure = mapped else {
            Issue.record("expected .syncFailure, got \(mapped)")
            return
        }
    }

    @Test("A non-CloudKit error falls back to syncFailure with its description")
    func nonCloudKit() {
        let raw = NSError(domain: "SomeOtherDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        let mapped = CloudKitErrorClassifier.classify(raw)
        #expect(mapped == .syncFailure(underlying: "boom"))
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter CloudKitErrorClassifierTests
```
Expected: compile error `cannot find 'CloudKitErrorClassifier' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift`:

```swift
import Foundation
import CloudKit

/// Maps a raw CloudKit/`NSError` to the `LillistError` taxonomy so steady-state
/// sync failures get a typed, surfaceable posture instead of an opaque blob.
///
/// Review blind-spot persist-5: a `LillistError.quotaExceeded` case existed but
/// nothing populated it. The four codes singled out here are the ones a healthy
/// account actually hits in steady state:
///
/// - `.quotaExceeded`       → the user's iCloud storage is full (actionable).
/// - `.requestRateLimited`  → back off and retry (Core Data's mirror already
///                            honors the `CKErrorRetryAfterKey`; we surface it).
/// - `.serverRejectedRequest` / `.zoneBusy` → transient server-side conditions.
///
/// Everything else collapses to `.syncFailure(underlying:)` carrying the
/// localized description, preserving today's behavior for unmodeled codes.
public enum CloudKitErrorClassifier {
    public static func classify(_ error: Error) -> LillistError {
        let ns = error as NSError
        guard ns.domain == CKErrorDomain, let code = CKError.Code(rawValue: ns.code) else {
            return .syncFailure(underlying: ns.localizedDescription)
        }
        switch code {
        case .quotaExceeded:
            return .quotaExceeded(resource: "iCloud")
        case .requestRateLimited:
            return .syncFailure(underlying: "CloudKit rate limited the request; will retry.")
        case .serverRejectedRequest:
            return .syncFailure(underlying: "CloudKit rejected the request.")
        case .zoneBusy:
            return .syncFailure(underlying: "CloudKit zone is busy; will retry.")
        default:
            return .syncFailure(underlying: ns.localizedDescription)
        }
    }
}
```

Then route `CloudKitEventBridge.translate` through it. In `CloudKitEventBridge.swift`, replace line 120:

```swift
        let mapped: LillistError? = event.error.map { LillistError.syncFailure(underlying: ($0 as NSError).localizedDescription) }
```

with:

```swift
        let mapped: LillistError? = event.error.map { CloudKitErrorClassifier.classify($0) }
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter CloudKitErrorClassifierTests
```
Expected: all five tests pass. Confirm the bridge suite still passes:
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter CloudKitEventBridgeTests
```
Expected: all `CloudKitEventBridge` tests still pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/CloudKitErrorClassifier.swift Packages/LillistCore/Sources/LillistCore/Sync/CloudKitEventBridge.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitErrorClassifierTests.swift && git commit -m "feat(sync): classify steady-state CKError into LillistError taxonomy

Adds CloudKitErrorClassifier mapping quotaExceeded/requestRateLimited/
serverRejectedRequest/zoneBusy onto LillistError, and routes
CloudKitEventBridge.translate through it so the sync-status surface
shows an actionable typed error instead of an opaque blob (persist-5)."
```

---

## Task 7: Two-store convergence integration test (persist-2 + notif-2 end-to-end)

A single `swift test` worker can't run two live `NSPersistentCloudKitContainer`s talking to real iCloud, but it *can* run two `PersistenceController`s over the **same on-disk SQLite file** to exercise the cross-process convergence path (which is exactly what CloudKit imports look like to Core Data: a foreign write merged into your store, posting `NSPersistentStoreRemoteChange`). This asserts the whole chain: stable-UUID preferences converge to one row, and a `lastFiredAt` write on "device A" drives a reconcile-affecting diff on "device B".

**Files:**
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift` (append a two-store suite)

- [ ] **Step 1: Write the failing test** — append a new suite to `RemoteChangeReconcilerTests.swift` (after the closing `}` of `struct RemoteChangeReconcilerTests`):

```swift
@Suite("Two-store convergence (shared on-disk file)")
struct TwoStoreConvergenceTests {
    /// A unique temp .sqlite path; cleaned up by the test.
    private static func tempStoreURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LillistConvergence-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Lillist.sqlite")
    }

    private static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Both controllers over one file see exactly one AppPreferences row after normalization")
    func preferencesConvergeToOneRow() async throws {
        let url = Self.tempStoreURL()
        defer { Self.cleanup(url) }

        // LocalOnly keeps the runtime path off live CloudKit while still using
        // the on-disk store + history tracking the convergence relies on.
        let cfgA = StoreConfiguration.onDisk(url: url, syncMode: .localOnly)
        let a = try await PersistenceController(configuration: cfgA)
        let prefsA = PreferencesStore(persistence: a)
        _ = try await prefsA.read()   // materialize the canonical row on A

        let cfgB = StoreConfiguration.onDisk(url: url, syncMode: .localOnly)
        let b = try await PersistenceController(configuration: cfgB)
        let prefsB = PreferencesStore(persistence: b)
        _ = try await prefsB.read()   // B must adopt the same well-known id

        try await prefsA.normalizeSingletons()
        try await prefsB.normalizeSingletons()

        #expect(try await prefsA.rowCount() == 1)
        #expect(try await prefsB.rowCount() == 1)
    }

    @Test("A lastFiredAt write on store A surfaces the task via the reconciler diff on store B")
    func lastFiredConvergence() async throws {
        let url = Self.tempStoreURL()
        defer { Self.cleanup(url) }

        let a = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let tasksA = TaskStore(persistence: a)
        let specsA = NotificationSpecStore(persistence: a)
        let taskID = try await tasksA.create(title: "Sync me")
        let specID = try await specsA.add(taskID: taskID, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)

        // Open "device B" over the same file and let it see A's rows.
        let b = try await PersistenceController(configuration: .onDisk(url: url, syncMode: .localOnly))
        let bCtx = b.container.viewContext

        // Snapshot B's history watermark BEFORE A writes lastFiredAt, so the
        // diff covers exactly the new transaction.
        let tokenStore = PersistentHistoryTokenStore(suiteName: "TwoStore-\(UUID().uuidString)")
        tokenStore.lastToken = try await bCtx.perform {
            let req = NSPersistentHistoryChangeRequest.fetchHistory(after: nil)
            let result = try bCtx.execute(req) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction])?.last?.token
        }

        // Device A records the fire (a different author than B's localAuthor —
        // both are "Lillist.app" here, so to model a *foreign* import we write
        // through a throwaway author on a background context).
        let foreignCtx = a.container.newBackgroundContext()
        foreignCtx.transactionAuthor = "DeviceA.import"
        try await foreignCtx.perform {
            let req = NSFetchRequest<NotificationSpec>(entityName: "NotificationSpec")
            req.predicate = NSPredicate(format: "id == %@", specID as CVarArg)
            let m = try foreignCtx.fetch(req).first!
            m.lastFiredAt = Date(timeIntervalSince1970: 9_000_000)
            try foreignCtx.save()
        }

        // Pull A's change into B and run the reconciler diff against the new
        // history. A short poll absorbs cross-coordinator merge latency.
        var affected: [UUID] = []
        for _ in 0..<50 {
            await bCtx.perform { bCtx.refreshAllObjects() }
            let after = tokenStore.lastToken
            let changes: [RemoteChangeReconciler.SyntheticChange] = try await bCtx.perform {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
                guard let result = try bCtx.execute(request) as? NSPersistentHistoryResult,
                      let txns = result.result as? [NSPersistentHistoryTransaction] else { return [] }
                var out: [RemoteChangeReconciler.SyntheticChange] = []
                for txn in txns {
                    for change in txn.changes ?? [] {
                        out.append(.init(
                            changedObjectID: change.changedObjectID,
                            entityName: change.changedObjectID.entity.name ?? "",
                            changedProperties: change.updatedProperties.map { Set($0.map(\.name)) } ?? [],
                            author: txn.author
                        ))
                    }
                }
                return out
            }
            affected = try await RemoteChangeReconciler.affectedTaskIDs(
                from: changes,
                localAuthor: PersistenceController.localTransactionAuthor,
                in: bCtx
            )
            if affected.isEmpty == false { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(affected == [taskID])
    }
}
```

- [ ] **Step 2: Run the test, expect failure (or pass)** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TwoStoreConvergenceTests
```
Expected on first run: both tests should pass against the code from Tasks 2–5. If `lastFiredConvergence` is flaky because the second on-disk container can't observe the first's writes without an explicit refresh, the polling loop + `refreshAllObjects()` already compensates; if it still fails, treat it as a real signal that the history fetch on a separate coordinator isn't seeing the cross-process write and widen the poll bound to `0..<100`. Do not weaken the `affected == [taskID]` assertion.

- [ ] **Step 3: Implement the minimal change** — none beyond Tasks 2–5; this task is integration coverage only. If `preferencesConvergeToOneRow` fails because B mints a second random-UUID row before `normalizeSingletons`, that is the bug the task is meant to catch — verify `fetchOrCreateSingleton` adopts the legacy id (Task 2) and `normalizeSingletons` collapses extras.

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TwoStoreConvergenceTests
```
Expected: both tests pass.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/Persistence/RemoteChangeReconcilerTests.swift && git commit -m "test(persistence): two-store convergence over a shared on-disk file

Exercises the full cross-process path: AppPreferences converges to one
well-known-UUID row across two controllers, and a foreign-author
lastFiredAt write on store A surfaces the affected taskID via the
reconciler diff on store B (persist-2, notif-2 end-to-end)."
```

---

## Task 8: Wire the reconciler + normalization into the iOS composition root

The pure pieces are useless until bootstrap runs them. `AppEnvironment` builds the scheduler and preferences store (lines 92–133); add (a) a one-shot `normalizeSingletons()` call and (b) a long-lived `RemoteChangeReconciler` whose callback fans out to `scheduler.reconcile(taskID:)`. This task changes app-target code only — no LillistCore signature changes — and is verified by an app-target build (Claude Code can't sign, so use the no-sign flags).

**Files:**
- Modify: `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (around lines 92–133 for construction; add a stored property + a `bootstrap`-adjacent call)

- [ ] **Step 1: Read the bootstrap region** — read `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` lines 40–270 to find (a) where stored `let` properties are declared, (b) the `bootstrap()`/launch hook where `preferencesPartitionMigrator.runIfNeeded()` and `scheduler.bootstrap()` are invoked, and (c) the App Group id constant. Confirm the exact method name that runs at launch.

- [ ] **Step 2: Add the stored property** — add to the stored-property block (next to `let notificationScheduler: NotificationScheduler` near line 55):

```swift
    /// Drives notification reconciliation from CloudKit imports (review
    /// notif-2). Retained for the app's lifetime; deinit removes its observer.
    let remoteChangeReconciler: RemoteChangeReconciler
```

- [ ] **Step 3: Construct it after the scheduler** — immediately after `self.taskStore.notificationScheduler = scheduler` (line 133), add:

```swift
        // Remote-change-driven reconcile: when CloudKit imports another
        // device's notification fire, reconcile the affected tasks so this
        // device drops its now-stale pending requests.
        let historyTokens = PersistentHistoryTokenStore(appGroupID: appGroupID)
        self.remoteChangeReconciler = RemoteChangeReconciler(
            persistence: persistence,
            tokenStore: historyTokens
        ) { [weak scheduler] affectedTaskIDs in
            guard let scheduler else { return }
            for taskID in affectedTaskIDs {
                await scheduler.reconcile(taskID: taskID)
            }
        }
```

(If `appGroupID` is not in scope at this point in `init`, use the same source the existing `DevicePreferencesStore(appGroupID: appGroupID)` call on line 217 uses — confirm in Step 1 and substitute the exact identifier.)

- [ ] **Step 4: Start it + normalize at launch** — in the launch hook found in Step 1 (the method that already calls `await preferencesPartitionMigrator.runIfNeeded()` / `await notificationScheduler.bootstrap()`), add, after the partition migrator call:

```swift
        // One-shot CloudKit singleton convergence + catch-up reconcile for any
        // imports that arrived while the app wasn't running, then start
        // observing live remote changes.
        try? await preferencesStore.normalizeSingletons()
        await remoteChangeReconciler.processPendingHistory()
        remoteChangeReconciler.start()
```

- [ ] **Step 5: Verify the app-target build** —
```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```
Expected: `** BUILD SUCCEEDED **` with no new warnings (warnings-as-errors). If the build complains that `appGroupID` isn't in scope where the reconciler is constructed, move the `PersistentHistoryTokenStore` construction down to where `appGroupID` is defined and pass it in, or hoist the `appGroupID` resolution above line 133.

- [ ] **Step 6: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/App/AppEnvironment.swift && git commit -m "feat(ios): wire remote-change reconcile + singleton normalization at launch

AppEnvironment now normalizes the AppPreferences singleton once and runs
a RemoteChangeReconciler that fans CloudKit-import notification fires out
to scheduler.reconcile(taskID:), with launch-time catch-up (persist-2,
notif-2)."
```

---

## Task 9: Document the conventions in engineering-notes.md

Append a single append-only entry capturing the four non-obvious rules a future contributor would otherwise rediscover the hard way: the well-known singleton UUID, the transaction-author convention, the kept merge-policy rationale, and the history-token diffing pattern.

**Files:**
- Modify: `docs/engineering-notes.md` (append)

- [ ] **Step 1: Read the tail of the notes file** — read the last ~30 lines of `docs/engineering-notes.md` to match the existing bullet/heading style and confirm the append point.

- [ ] **Step 2: Append the entry** — add to the end of `docs/engineering-notes.md`:

```markdown

## CloudKit cross-device convergence (2026-05-28)

- **`AppPreferences` uses a well-known constant id, not `UUID()`.**
  `PreferencesStore.singletonID` is a fixed UUID literal. Before this,
  every device minted its own random id, so CloudKit mirrored two
  distinct "singleton" records and the devices flip-flopped. Never
  regenerate the literal — existing stores depend on it.
  `normalizeSingletons()` (called once at bootstrap) collapses any
  legacy multi-row store down to one canonical row by id-sort, keeping
  the first and reassigning it `singletonID`. It is idempotent.
- **`viewContext.transactionAuthor`/`.name` are set to
  `PersistenceController.localTransactionAuthor` at store load.** This
  is load-bearing: the persistent-history diff in
  `RemoteChangeReconciler` separates our own writes from CloudKit
  imports purely by author. Removing it makes every local write look
  like a remote change and triggers redundant reconcile cycles.
- **Steady-state merge policy stays `mergeByPropertyObjectTrump` — on
  purpose.** `CloudKitErrorClassifier` now gives `CKError` a typed
  posture, but the conflict policy is intentionally last-writer-wins
  per property. The known cost is that a concurrent edit to the *same
  property* on another device is silently discarded on merge; per-field
  CRDT reconciliation is YAGNI until a real conflict report appears.
  Documented here so the choice is explicit, not inherited.
- **History-token diffing resumes from a persisted watermark.**
  `PersistentHistoryTokenStore` archives the `NSPersistentHistoryToken`
  (via `NSKeyedArchiver`, `requiringSecureCoding: true`) into App-Group
  `UserDefaults`. The reconciler fetches `fetchHistory(after:)` the
  watermark, flattens transactions to `SyntheticChange`s, and only
  reacts to `NotificationSpec.lastFiredAt` changes from a foreign
  author — then advances the watermark. The diffing core
  (`RemoteChangeReconciler.affectedTaskIDs`) is a `nonisolated static`
  pure function so it's unit-testable without a live container.
```

- [ ] **Step 3: Verify the doc renders** —
```bash
cd /Volumes/Code/mikeyward/Lillist && tail -40 docs/engineering-notes.md
```
Expected: the new `## CloudKit cross-device convergence (2026-05-28)` section is present and well-formed.

- [ ] **Step 4: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add docs/engineering-notes.md && git commit -m "docs(engineering-notes): record CloudKit convergence conventions

Documents the well-known AppPreferences UUID, the transaction-author
convention, the kept merge-policy rationale, and the history-token
diffing pattern (persist-2, conc-3, notif-2, persist-5)."
```

---

## Task 10: Full-suite regression gate

Run the whole `LillistCore` suite to prove nothing else regressed (the scheduler, sync, and persistence suites in particular touch the surfaces this plan changed).

**Files:** none (verification only).

- [ ] **Step 1: Run the full LillistCore suite** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -30
```
Expected: the run ends with `Test run with N tests passed` (N ≥ 649 + the new tests from this plan), zero failures, zero warnings.

- [ ] **Step 2: Spot-check the directly-touched suites by name** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter "PreferencesStoreSingletonTests|RemoteChangeReconcilerTests|TwoStoreConvergenceTests|PersistentHistoryTokenStoreTests|CloudKitErrorClassifierTests|NotificationSpecStoreTests|PersistenceControllerCloudKitTests"
```
Expected: every named suite passes.

- [ ] **Step 3: Confirm the iOS app target still builds (final guard)** —
```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: No commit** — this task only verifies; the work was committed task-by-task. If anything fails, fix it under the owning task's rhythm (Red-Green) rather than patching here.

---

## Self-review checklist

- [ ] **`persist-2`** (stable `AppPreferences` UUID + one-time normalization) — closed by **Task 2** (`PreferencesStore.singletonID` + `normalizeSingletons` + `fetchOrCreateSingleton` adoption) and proven cross-process by **Task 7** (`preferencesConvergeToOneRow`); wired at launch by **Task 8**.
- [ ] **`conc-3`** (set `viewContext.transactionAuthor`/`.name` after store load) — closed by **Task 1** (`PersistenceController.localTransactionAuthor` + `viewContext` assignment), asserted by `viewContextTransactionAuthorIsSet`.
- [ ] **`notif-2`** (remote-change reconcile on import + at-most-one default spec per `(taskID, kind)`) — the dedup half is closed by **Task 3** (`NotificationSpecStore.add` guard); the import-driven reconcile half is closed by **Task 4** (`RemoteChangeReconciler`) on top of **Task 5**'s token store, proven end-to-end by **Task 7** (`lastFiredConvergence`), and wired by **Task 8**.
- [ ] **`persist-5`** (steady-state `CKError` quota/rate-limit handling + reconsider the blunt store-wide `mergeByPropertyObjectTrump`) — closed by **Task 6** (`CloudKitErrorClassifier` + `CloudKitEventBridge.translate` routing) for the error posture, and by **Task 1**'s inline rationale comment + **Task 9**'s engineering note for the deliberately-kept merge policy (explicit decision, not silent inheritance).
- [ ] **Strengths preserved:** synchronous same-actor `AsyncStream` registration in `CloudKitEventBridge`/`SyncStatusMonitor` is untouched (only the error-mapping line in `translate` changes); the DTO boundary holds (no `NSManagedObject` escapes — `RemoteChangeReconciler.affectedTaskIDs` returns `[UUID]`, and `SyntheticChange` carries an opaque `NSManagedObjectID`, not a managed object); `Calendar`-based date math untouched; container/presenter UI split untouched (Task 8 is composition-root wiring only).
- [ ] **No `.xcdatamodel` edit** — this plan adds no Core Data attributes or entities, so the `CompileCoreDataModel` mtime touch ritual is not needed. (`AppPreferences.id` and `NotificationSpec.lastFiredAt` already exist in the model.)
- [ ] **Warnings-as-errors honored** — every new file compiles under strict concurrency on the LillistCore source target; app-target build verified clean in Tasks 8 and 10.
- [ ] **Conventional commits, small + focused** — one commit per task (Tasks 1–6, 8, 9), integration coverage isolated (Task 7), verification-only (Task 10).
