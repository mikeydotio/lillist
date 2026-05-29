# Store-Swap Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the destructive LocalOnly↔iCloudSync store swap transactional and crash-safe, and give the migration state machine real executing test coverage with failure injection so the swap fix is actually verified.

**Architecture:** Introduce a `PersistenceReconfiguring` protocol seam over `PersistenceHost`'s two members the coordinator touches (`currentMode`, `reconfigure(to:)`), so `runMigration`/`restoreFromBackup` can run end-to-end under `swift test` with a `FakePersistenceReconfigurer` — no live `NSPersistentCloudKitContainer`. Make `PersistenceHost.flushAndSwap` transactional (capture the original mode's `NSPersistentStoreDescription` — rebuilt via `PersistenceController.makeStoreDescription` so it carries `cloudKitContainerOptions`, since the live store doesn't surface them — wrap remove+add in do/catch inside one `viewContext.perform`, re-add the captured original via the description-taking `addPersistentStore(with:completionHandler:)` on add-failure so iCloud mirroring is preserved on rollback (Roadmap #1), surface `LillistError.storeUnavailable` if rollback also throws), reorder `runMigration` so the store is removed before any file move, quarantine by copy then delete, tie `quarantineBackupID` to the on-disk folder name, and precondition a non-empty local store before the irreversible erase. Add an app-hosted iOS unit-test target with a real `CFBundleIdentifier` so the live-container swap tests stop silently skipping, plus a meta-test asserting `liveSwapAllowed == true` under that host.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`, `@Test`/`#expect`), Core Data via `NSPersistentCloudKitContainer`, SwiftPM (`LillistCore`), xcodegen for the iOS app-hosted test target.

**Source findings:** persist-3, sync-1, sync-3, sync-4, sync-7, conc-4, test-1, test-2.

---

## File Structure

### Create

- `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift` — the protocol seam (`var currentMode`, `func reconfigure(to:)`) that `MigrationCoordinator` depends on instead of the concrete `PersistenceHost`; `PersistenceHost` conforms.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/FakePersistenceReconfigurer.swift` — actor fake implementing `PersistenceReconfiguring`; records phase-ordered `reconfigure` calls, can throw on the Nth call for failure injection.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/ThrowingMigrationJournalStore.swift` — decorator over an underlying `MigrationJournalStore` that throws on the Nth `write` so a secondary catch-write failure can't mask the original error.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift` — the executing (ungated) state-machine tests: phase order, journal transitions, eraser `callCount`, `cancelAllPending` ordering, failure injection per phase.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRecoveryTests.swift` — ungated `restoreFromBackup` tests (happy path + no-backup `storeUnavailable`).
- `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineRestoreTests.swift` — direct `QuarantineManager.restore` / `latestQuarantinedStore` / `quarantineStore` round-trip tests.
- `Apps/Lillist-iOS/Tests/AppHostedTests/LiveSwapHostMetaTests.swift` — host-gated meta-test asserting `liveSwapAllowed == true` so a misconfigured host can't masquerade as green.

### Modify

- `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift` — conform to `PersistenceReconfiguring`; make `flushAndSwap` transactional (capture the original mode's description, do/catch, rollback re-add via the description-taking `addPersistentStore(with:)` so `cloudKitContainerOptions` round-trip — Roadmap #1 — atomic single `perform`); add the `addStore(_:to:)` description-add helper and the `lastRollbackDescription` capture seam.
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` — accept `any PersistenceReconfiguring`; reorder so store is removed before file move; quarantine by copy (delete original only after clean remove); tie `quarantineBackupID` to the on-disk folder name; precondition non-empty local store before the erase in `replaceICloudWithLocal`.
- `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift` — add `copyStore(at:)` (copy-not-move) returning a `QuarantinedBackup` value carrying the folder name; keep `quarantineStore` (move) for the recovery re-quarantine path.
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift` — change `quarantineBackupID: UUID?` → `quarantineFolderName: String?` (the actual on-disk folder), keeping a deprecated decode path for old journals.
- `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift` — point the gated live tests at the new initializer; keep them gated, but they now coexist with the ungated executing tests.
- `Apps/Lillist-iOS/project.yml` — add the `Lillist-iOSAppHostedTests` target (real `TEST_HOST` = the app) + wire into the scheme.
- `CLAUDE.md` — document the app-hosted test command + the `liveSwapAllowed` meta-test rationale.

---

## Task 1: Carve the `PersistenceReconfiguring` protocol seam

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift`
- Modify `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift` (add conformance, lines 37–99)

- [ ] **Step 1: Write the protocol file.** Create `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift` with the complete content:

```swift
import Foundation

/// The minimal surface `MigrationCoordinator` needs from the
/// persistence layer: read the canonical sync mode and run the
/// structural store swap.
///
/// Plan 21 hardening: extracting this seam lets `runMigration` and
/// `restoreFromBackup` run end-to-end under `swift test` against a
/// `FakePersistenceReconfigurer`, instead of requiring a live
/// `NSPersistentCloudKitContainer` (whose `NSCloudKitMirroringDelegate`
/// teardown crashes the swift-test binary — see `StoreLevelModeSwapSpike`
/// for the long version). `PersistenceHost` is the production conformer;
/// the live container swap stays covered by the host-gated tests.
///
/// Both members are `async` because the production conformer is an
/// `actor`; conformers are `Sendable` so the coordinator can hold one
/// across the `@MainActor` boundary.
public protocol PersistenceReconfiguring: Sendable {
    /// The canonical sync mode the underlying store is currently
    /// attached as.
    var currentMode: SyncMode { get async }

    /// Switch the underlying store to `newMode`. Implementations must
    /// be transactional: on any failure the store stays attached in
    /// its pre-call mode (no store-less coordinator).
    func reconfigure(to newMode: SyncMode) async throws
}
```

- [ ] **Step 2: Run the build, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: the build succeeds (the protocol compiles standalone). If it fails, the only plausible cause is a `SyncMode` import gap — `SyncMode` is in the same module, so no import is needed. Proceed once green.

- [ ] **Step 3: Add the conformance to `PersistenceHost`.** In `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift`, change the actor declaration on line 37 from:

```swift
public actor PersistenceHost {
```

to:

```swift
public actor PersistenceHost: PersistenceReconfiguring {
```

The actor already exposes `public private(set) var currentMode: SyncMode` (line 39) and `public func reconfigure(to newMode: SyncMode) async throws` (line 95), which satisfy the protocol's `var currentMode: SyncMode { get async }` and `func reconfigure(to:)` requirements verbatim — actor-isolated stored properties satisfy `get async` requirements. No other change is needed in this file for this task.

- [ ] **Step 4: Run the build, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: `Build complete!` with no warnings (warnings are errors on this target).

- [ ] **Step 5: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceReconfiguring.swift Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift && git commit -m "refactor(sync): extract PersistenceReconfiguring seam for testable migrations"
```

---

## Task 2: Repoint `MigrationCoordinator` at the protocol (still compiles, no behavior change)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (the stored `host` property line 32, the `init` parameter line 48)

This is a pure type-narrowing refactor: nothing about behavior changes, so the existing gated tests still pass under xcodebuild and the file still compiles under `swift test`. It unlocks Task 6's executing tests.

- [ ] **Step 1: Narrow the stored property type.** In `MigrationCoordinator.swift`, change line 32 from:

```swift
    private let host: PersistenceHost
```

to:

```swift
    private let host: any PersistenceReconfiguring
```

- [ ] **Step 2: Narrow the `init` parameter type.** In the same file, change the `init` parameter (line 48) from:

```swift
        host: PersistenceHost,
```

to:

```swift
        host: any PersistenceReconfiguring,
```

No other lines change — the body only calls `host.reconfigure(to:)` (line 135, 194) and reads `await host.currentMode` (line 158), both of which the protocol provides.

- [ ] **Step 3: Run the package build, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: `Build complete!`. `AppEnvironment` passes a concrete `PersistenceHost` (which conforms), so no app-side change is required.

- [ ] **Step 4: Run the existing migration tests, expect the same skip behavior.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorTests 2>&1 | tail -25
```

Expected: `resumeReadsJournal` passes; `disableNow` and `replaceICloudWithLocal` are skipped (`liveSwapAllowed == false` under swift test) — exactly the pre-refactor state. No failures.

- [ ] **Step 5: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift && git commit -m "refactor(sync): MigrationCoordinator depends on PersistenceReconfiguring"
```

---

## Task 3: Make `PersistenceHost.flushAndSwap` transactional (sync-4, conc-4)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift` (`flushAndSwap`, lines 105–125)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceHostTests.swift` (add a rollback test)

The current `flushAndSwap` does the flush in one `perform`, then `coordinator.remove(store)` and `addPersistentStore(...)` *outside* any guarded block. If `addPersistentStore` throws, the coordinator is left store-less with no rollback — every subsequent operation hits a store-less coordinator until relaunch (sync-4). Fix: capture the original store's *description* (not just the live store's `options`), do the remove+add inside one `viewContext.perform` critical section (conc-4), and on add-failure re-add the captured original; if that re-add also throws, surface `storeUnavailable`.

**CloudKit-options round-trip (Roadmap #1).** The naïve capture — snapshotting `store.options` / `store.type` / `store.url` from the live `NSPersistentStore` and re-adding via `coordinator.addPersistentStore(type:configuration:at:options:)` — **silently drops CloudKit mirroring on rollback**. `NSPersistentCloudKitContainerOptions` lives on the *description* (`NSPersistentStoreDescription.cloudKitContainerOptions`, set in `PersistenceController.makeStoreDescription` only when `syncMode == .iCloudSync`), and it is **not** mirrored back into the live store's `options` dictionary — `StoreLevelModeSwapSpike.swapMutatesDescription` documents exactly this (it can only assert the post-swap store's `url`, not its CloudKit options, because the live store doesn't expose them). So rolling back a half-added iCloud store with the `(type:configuration:at:options:)` overload would re-attach a *plain local* store: data intact, **mirroring lost** — the precise latent bug Roadmap #1 calls out.

The correct rollback therefore (a) captures the **original `SyncMode`** (`currentMode`) before `remove`, (b) rebuilds the original description with `PersistenceController.makeStoreDescription(for: configuration(for: originalMode))` — which carries `cloudKitContainerOptions` through verbatim (it is the same static factory production uses, so the options are constructed identically: private-scope `NSPersistentCloudKitContainerOptions(containerIdentifier:)`) — and (c) re-adds via the **description-taking** coordinator API `addPersistentStore(with:completionHandler:)` so the `cloudKitContainerOptions` are actually honored on re-attach. The `(type:configuration:at:options:)` overload **cannot** carry `cloudKitContainerOptions` and so must not be used for the rollback. (`addPersistentStoreWithDescription:` is `NS_SWIFT_DISABLE_ASYNC`, so it surfaces in Swift only as the completion-handler form `addPersistentStore(with:completionHandler:)` — *not* an `async throws` call. For an on-disk SQLite store the handler fires **synchronously on the calling queue**, so a tiny local-var bridge — capture the handler's `error`, then `throw` it — keeps the re-add inside the one `viewContext.perform` critical section without a continuation hop. See the `addStore(_:to:)` helper in Step 3.)

- [ ] **Step 1: Write the failing test.** In `Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceHostTests.swift`, add **two** tests inside the `PersistenceHostTests` struct (after `reconfigureSwapsAndPreservesData`, before the closing brace).

The first (live, host-gated) test drives a simulated add-failure and asserts the original store is still attached and the mode is unchanged afterward:

```swift
    @Test("Failed reconfigure rolls back to the original store (no store-less coordinator)", .enabled(if: liveSwapAllowed))
    func failedReconfigureRollsBack() async throws {
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)
        let controller = await host.controller
        // Seed a row so we can prove the original store survives a
        // rollback (count stays readable post-failure).
        let ctx = controller.container.viewContext
        try await ctx.perform {
            let row = LillistTask(context: ctx)
            row.id = UUID()
            row.title = "rollback-test"
            row.statusRaw = 0
            row.createdAt = Date()
            row.modifiedAt = Date()
            row.position = 0
            try ctx.save()
        }

        // Arm the test seam so the next swap re-adds the original store
        // (the rollback path) and then throws, without corrupting a
        // real on-disk store.
        await host.simulateAddFailureOnNextSwap()
        await #expect(throws: (any Error).self) {
            try await host.reconfigure(to: .localOnly)
        }

        // The original store must still be attached: a count succeeds
        // and the mode is unchanged.
        let count = try await ctx.perform {
            try ctx.count(for: NSFetchRequest<LillistTask>(entityName: "LillistTask"))
        }
        #expect(count == 1)
        #expect(await host.currentMode == .iCloudSync)
    }
```

The second test is the **Roadmap #1 CloudKit-options proof**. Because the framework does not expose `cloudKitContainerOptions` back through the live `NSPersistentStore` (only the *description* carries them — see `StoreLevelModeSwapSpike.swapMutatesDescription`, which can assert only the store's `url`), a true unit assertion on the *re-added live store's* CloudKit options is **not reachable without a live container**. We therefore assert against the **value object the rollback actually re-added** — the captured `lastRollbackDescription` exposed via `rollbackDescriptionForTesting()`. This proves the rollback re-attaches a *mirroring* iCloud store, not a downgraded plain-local one. This test does **not** touch the live container (the seam throws before the real `addPersistentStore`), so it runs **everywhere**, including under `swift test` — no `liveSwapAllowed` gate:

```swift
    @Test("Rollback from a half-added iCloud store preserves cloudKitContainerOptions (Roadmap #1)")
    func rollbackPreservesCloudKitOptions() async throws {
        // Build a host attached as .iCloudSync. We use the in-memory
        // controller so no live container/CloudKit teardown runs — the
        // seam throws before the real addPersistentStore, so we never
        // need an on-disk store. The rollback description is built from
        // the captured ORIGINAL mode, which is .iCloudSync here.
        let url = Self.freshStoreURL()
        let host = try await PersistenceHost.make(initialMode: .iCloudSync, storeURL: url)

        // Arm the simulated add-failure: the swap to .localOnly will
        // remove the store, fail the re-add, and roll back to the
        // original .iCloudSync description.
        await host.simulateAddFailureOnNextSwap()
        await #expect(throws: (any Error).self) {
            try await host.reconfigure(to: .localOnly)
        }

        // The rollback description must carry CloudKit options matching
        // the original container — i.e. mirroring is restored intact,
        // not silently dropped to a plain local store.
        let rollbackDesc = await host.rollbackDescriptionForTesting()
        #expect(rollbackDesc != nil)
        #expect(rollbackDesc?.cloudKitContainerOptions != nil)
        #expect(rollbackDesc?.cloudKitContainerOptions?.containerIdentifier
                == StoreConfiguration.defaultCloudKitContainerIdentifier)
        #expect(rollbackDesc?.cloudKitContainerOptions?.databaseScope == .private)
        // And the persistent-history / remote-change flags survive too,
        // so a later re-enable of iCloudSync still works.
        #expect((rollbackDesc?.options[NSPersistentHistoryTrackingKey] as? NSNumber)?.boolValue == true)
    }
```

> **Reachability note (stated explicitly per the brief):** asserting `cloudKitContainerOptions` on the *live re-added store* is impossible without a live container *and* even then the framework doesn't surface it back through `NSPersistentStore` — `StoreLevelModeSwapSpike` documents this. The assertion above therefore targets the captured-description value object the rollback re-adds (`lastRollbackDescription`). That value is the *exact* `NSPersistentStoreDescription` instance handed to `coordinator.addPersistentStore(with:)`, so proving it carries the options proves the live re-add carries them.

- [ ] **Step 2: Run the test, expect failure.** The new `rollbackPreservesCloudKitOptions` test is ungated, so the fastest Red signal is the SPM build (it references seams that don't exist yet):

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter PersistenceHostTests 2>&1 | tail -10
```

Expected: compile failure — `value of type 'PersistenceHost' has no member 'simulateAddFailureOnNextSwap'` and `... 'rollbackDescriptionForTesting'`. This is the Red state; Step 3 adds both the production transactional path and the two test seams. (`failedReconfigureRollsBack` is host-gated and actually *executes* under the app-hosted target from Task 9; `rollbackPreservesCloudKitOptions` is ungated and executes here under `swift test` once Step 3 lands.)

- [ ] **Step 3: Implement the transactional `flushAndSwap` plus the failure + capture seams.** In `PersistenceHost.swift`, first add the test-only injection flag, a capture slot for the rollback description, and the seam methods. Add these two stored properties right after `private let storeURL: URL?` (line 47):

```swift
    /// Test seam: when set, the next `flushAndSwap` re-adds the
    /// original store but then *throws* to simulate an
    /// `addPersistentStore` failure, exercising the rollback path
    /// without corrupting a real on-disk store. Reset after one use.
    private var failAddOnNextSwap = false

    /// Test seam: the `NSPersistentStoreDescription` the last rollback
    /// re-added (or *would* re-add). Lets a unit test assert that the
    /// rollback path preserves `cloudKitContainerOptions` even when the
    /// live container can't be inspected for them (the framework does
    /// not surface CloudKit options back through `NSPersistentStore`).
    /// Roadmap #1: this is the value-object proof that mirroring is
    /// restored, not silently downgraded to a plain local store.
    private(set) var lastRollbackDescription: NSPersistentStoreDescription?
```

Add these methods right after `make(...)` (after line 78):

```swift
    /// Test seam (see `failAddOnNextSwap`). Arms a single simulated
    /// add-failure on the next `reconfigure`.
    func simulateAddFailureOnNextSwap() {
        failAddOnNextSwap = true
    }

    /// Test seam (see `lastRollbackDescription`). Reads the description
    /// the most recent rollback re-added, so a test can assert its
    /// `cloudKitContainerOptions` round-tripped.
    func rollbackDescriptionForTesting() -> NSPersistentStoreDescription? {
        lastRollbackDescription
    }
```

Then replace the entire `flushAndSwap` method (lines 105–125) with:

```swift
    /// Flush pending viewContext writes and run a store-level swap to
    /// the target mode. Transactional: captures the *original mode's
    /// description* (which carries `cloudKitContainerOptions` when the
    /// store was mirroring), removes + re-adds inside one
    /// `viewContext.perform` critical section, and on add-failure
    /// re-adds the original description so the coordinator is never left
    /// store-less *and* never silently downgraded from iCloud to plain
    /// local (sync-4, conc-4, Roadmap #1). Public so
    /// `MigrationCoordinator` can call it inside a larger phase sequence
    /// without re-implementing the recipe.
    private func flushAndSwap(to newMode: SyncMode) async throws {
        let ctx = controller.container.viewContext
        let coordinator = controller.container.persistentStoreCoordinator
        let shouldSimulateFailure = failAddOnNextSwap
        failAddOnNextSwap = false
        // Capture the ORIGINAL mode before the swap so we can rebuild a
        // faithful rollback description. `currentMode` is the mode the
        // store is attached as right now; `reconfigure` only advances it
        // after we return successfully.
        let originalMode = currentMode
        try await ctx.perform { [shouldSimulateFailure] in
            if ctx.hasChanges {
                try ctx.save()
            }
            // We only support a single attached store in production; in
            // tests there may be zero (in-memory) — bail in that case.
            guard let store = coordinator.persistentStores.first else { return }

            // Build the rollback description from the ORIGINAL mode via
            // the same static factory production uses. This is the only
            // path that carries `cloudKitContainerOptions` through — the
            // live `store.options` dictionary does NOT expose them
            // (see StoreLevelModeSwapSpike.swapMutatesDescription), so
            // we must rebuild the description, not snapshot the store.
            let rollbackDesc = PersistenceController.makeStoreDescription(
                for: self.configuration(for: originalMode)
            )

            try coordinator.remove(store)

            let configForNewMode = self.configuration(for: newMode)
            let desc = PersistenceController.makeStoreDescription(for: configForNewMode)
            do {
                if shouldSimulateFailure {
                    throw LillistError.storeUnavailable(reason: "simulated add failure (test seam)")
                }
                _ = try coordinator.addPersistentStore(
                    type: NSPersistentStore.StoreType(rawValue: desc.type),
                    configuration: nil,
                    at: desc.url!,
                    options: desc.options
                )
            } catch {
                // Roll back: re-add the ORIGINAL store via the
                // description-taking API so `cloudKitContainerOptions`
                // are honored — re-adding with
                // `(type:configuration:at:options:)` would drop them and
                // leave a plain local store. Record the description we
                // re-added so a unit test can assert the options
                // round-tripped (Roadmap #1). If even the rollback
                // fails, surface storeUnavailable — the caller's journal
                // is left .failed and recovery can restore a backup.
                self.lastRollbackDescription = rollbackDesc
                do {
                    try Self.addStore(rollbackDesc, to: coordinator)
                } catch let rollbackError {
                    throw LillistError.storeUnavailable(
                        reason: "Store swap failed and rollback also failed: \(error); rollback: \(rollbackError)"
                    )
                }
                throw error
            }
        }
    }

    /// Re-add a store from a full `NSPersistentStoreDescription` so
    /// `cloudKitContainerOptions` (and every other description-level
    /// field) is honored. `addPersistentStore(with:completionHandler:)`
    /// is `NS_SWIFT_DISABLE_ASYNC`, so we bridge its completion handler;
    /// for SQLite stores it fires synchronously on the calling queue,
    /// keeping the call inside the one `perform` critical section.
    private nonisolated static func addStore(
        _ description: NSPersistentStoreDescription,
        to coordinator: NSPersistentStoreCoordinator
    ) throws {
        var addError: Error?
        coordinator.addPersistentStore(with: description) { _, error in
            addError = error
        }
        if let addError { throw addError }
    }
```

Note: `reconfigure(to:)` (line 95) already sets `currentMode = newMode` only *after* `flushAndSwap` returns successfully — so a thrown error from `flushAndSwap` correctly leaves `currentMode` unchanged, which is also why `originalMode = currentMode` (captured at entry) is the correct mode to rebuild the rollback description from. No edit to `reconfigure` is needed.

Concurrency note (strict-concurrency target): `flushAndSwap` is actor-isolated, and `ctx.perform { … }` runs its closure synchronously *and inline* (the `await ctx.perform` form on the same cooperative thread), so writing `self.lastRollbackDescription` from inside the closure is a same-actor mutation — no hop, no data race. `addStore(_:to:)` is `nonisolated static` (pure parameter math, touches no actor state) so it's callable from inside the closure without an isolation hop. If the compiler flags the `self.lastRollbackDescription` write as a capture-of-non-Sendable across the `perform` boundary, hoist the assignment out: have the `perform` closure `throw` a small local error carrying the `rollbackDesc`, catch it just outside the closure (still inside the actor-isolated `flushAndSwap`), assign `lastRollbackDescription` there, and rethrow — but try the inline assignment first; it is the simplest correct form.

- [ ] **Step 4: Run the test, expect pass.** The ungated `rollbackPreservesCloudKitOptions` runs here under `swift test`; the host-gated `failedReconfigureRollsBack` runs under the app-hosted target created in Task 9. Verify the production code compiles and the package test suite is green:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -5 && swift test --package-path Packages/LillistCore --filter PersistenceHostTests 2>&1 | tail -10
```

Expected: `Build complete!`; `PersistenceHostTests` runs — `initRecordsMode`, `reconfigureSameModeIsNoop`, and the ungated `rollbackPreservesCloudKitOptions` pass under swift test (the latter asserts the captured rollback description's `cloudKitContainerOptions` round-trip — Roadmap #1 — without a live container); the live tests (`reconfigureSwapsAndPreservesData`, `failedReconfigureRollsBack`) skip under swift test. The full host-gated run happens in Task 9 Step 4.

> Note on `rollbackPreservesCloudKitOptions` reaching the rollback path on an in-memory host: `PersistenceHost.make` builds an *on-disk* `NSPersistentCloudKitContainer` (the factory is on-disk by URL), so `coordinator.persistentStores.first` is non-nil and the swap proceeds to the armed failure → rollback. If a future refactor makes `make` in-memory, `flushAndSwap`'s `guard …first != nil` would early-return and this test would need an explicit on-disk seed — call that out if it regresses.

- [ ] **Step 5: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceHost.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceHostTests.swift && git commit -m "fix(sync): transactional flushAndSwap rollback preserves cloudKitContainerOptions (sync-4, conc-4, Roadmap #1)"
```

---

## Task 4: Add `QuarantineManager.copyStore` (copy-not-move) returning a named backup (persist-3, sync-7)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift` (add type + method after line 44)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineRestoreTests.swift` (Create)

The current `quarantineStore` *moves* the SQLite triplet out from under the still-open container (persist-3). We add `copyStore(at:)` (copy, leave original in place — the coordinator removal in the reordered `runMigration` is what closes the connection) and return a `QuarantinedBackup` carrying the actual on-disk folder name so the journal can record it (sync-7). `quarantineStore` (move) is retained for the recovery re-quarantine path where the target store must be vacated.

- [ ] **Step 1: Write the failing test.** Create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineRestoreTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("QuarantineManager restore + copy-backup")
struct QuarantineRestoreTests {
    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-quarantine-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("copyStore leaves the original in place and returns a named backup")
    func copyLeavesOriginal() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("main".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: storeURL.appendingPathExtension("wal"))
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })

        let backup = try mgr.copyStore(at: storeURL)

        // Original survives (copy, not move).
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
        // Backup folder name is non-empty and the main file copied.
        #expect(backup.folderName.isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.path) == true)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.appendingPathExtension("wal").path) == true)
        // The folder name resolves back to the same store via the
        // by-name lookup.
        let resolved = try mgr.quarantinedStore(folderName: backup.folderName, filename: "Lillist.sqlite")
        #expect(resolved?.path == backup.storeURL.path)
    }

    @Test("restore copies a quarantined store back to the target")
    func restoreRoundTrip() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("original".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let backup = try mgr.copyStore(at: storeURL)

        // Wipe the live store, then restore.
        try FileManager.default.removeItem(at: storeURL)
        let restored = try mgr.restore(quarantinedStore: backup.storeURL, to: storeURL)
        #expect(restored.path == storeURL.path)
        #expect(try String(contentsOf: storeURL, encoding: .utf8) == "original")
    }

    @Test("latestQuarantinedStore finds the most recent copy backup")
    func latestFindsCopy() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data("data".utf8).write(to: storeURL)
        let mgr = QuarantineManager(rootDirectory: root, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        _ = try mgr.copyStore(at: storeURL)
        let latest = try mgr.latestQuarantinedStore(filename: "Lillist.sqlite")
        #expect(latest != nil)
        #expect(latest?.lastPathComponent == "Lillist.sqlite")
    }
}
```

- [ ] **Step 2: Run the test, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter QuarantineRestoreTests 2>&1 | tail -15
```

Expected: compile failure — `value of type 'QuarantineManager' has no member 'copyStore'` and `... 'quarantinedStore'`.

- [ ] **Step 3: Implement `QuarantinedBackup`, `copyStore`, and `quarantinedStore(folderName:)`.** In `QuarantineManager.swift`, add this nested value type and the two methods. Insert the struct just inside the `QuarantineManager` declaration, right after `public static let retentionInterval` (line 10):

```swift
    /// A quarantine backup created by `copyStore`. Carries the on-disk
    /// folder name so the migration journal can record exactly which
    /// archive to restore (sync-7).
    public struct QuarantinedBackup: Sendable, Equatable {
        /// The leaf folder name under `<root>/Quarantine/`, e.g. the
        /// unix timestamp string.
        public let folderName: String
        /// URL of the main `.sqlite` file inside the backup folder.
        public let storeURL: URL

        public init(folderName: String, storeURL: URL) {
            self.folderName = folderName
            self.storeURL = storeURL
        }
    }
```

Then add these two methods right after `quarantineStore(at:)` (after line 44):

```swift
    /// Copy the SQLite store (and its `-wal` / `-shm` sidecars, if
    /// present) into `<root>/Quarantine/<unix-timestamp>/`, leaving the
    /// original in place. Used as the pre-swap recovery anchor: the
    /// migration coordinator removes the store from the coordinator
    /// (closing the connection) and then this captures a clean copy
    /// without yanking the live file (persist-3). Returns a named
    /// backup so the journal can record the exact folder (sync-7).
    @discardableResult
    public func copyStore(at storeURL: URL) throws -> QuarantinedBackup {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        let folderName = String(Int(clock().timeIntervalSince1970))
        let quarantineDir = rootDirectory.appendingPathComponent("Quarantine/\(folderName)", isDirectory: true)
        try fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)

        let dest = quarantineDir.appendingPathComponent(storeURL.lastPathComponent)
        try fm.copyItem(at: storeURL, to: dest)

        for ext in ["wal", "shm"] {
            let sidecar = storeURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: sidecar.path) {
                let sidecarDest = dest.appendingPathExtension(ext)
                try fm.copyItem(at: sidecar, to: sidecarDest)
            }
        }
        return QuarantinedBackup(folderName: folderName, storeURL: dest)
    }

    /// Resolve the main `.sqlite` file for a backup folder recorded by
    /// `copyStore`. Returns `nil` when the folder or file no longer
    /// exists. Recovery uses this to restore the *exact* backup the
    /// journal recorded rather than guessing the latest.
    public func quarantinedStore(folderName: String, filename: String = "Lillist.sqlite") throws -> URL? {
        let candidate = rootDirectory
            .appendingPathComponent("Quarantine/\(folderName)", isDirectory: true)
            .appendingPathComponent(filename)
        return fm.fileExists(atPath: candidate.path) ? candidate : nil
    }
```

- [ ] **Step 4: Run the test, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter QuarantineRestoreTests 2>&1 | tail -12
```

Expected: `Test Suite 'QuarantineManager restore + copy-backup' passed` with 3 tests. Also re-run the existing `QuarantineManagerTests` to confirm `quarantineStore` (move) is untouched:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter QuarantineManagerTests 2>&1 | tail -8
```

Expected: all 5 existing tests still pass.

- [ ] **Step 5: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineRestoreTests.swift && git commit -m "feat(persist): add copy-not-move quarantine backup with named folder (persist-3, sync-7)"
```

---

## Task 5: Tie the journal to the on-disk folder name (sync-7)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift` (field rename, lines 60, 69, 77 + a custom decode for back-compat)
- Test `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift` (update the round-trip test)

The journal currently stores `quarantineBackupID: UUID?` (line 60), generated by the coordinator (`UUID()` at MigrationCoordinator.swift:169) and *never tied to the actual on-disk folder* (the unix-timestamp string). Recovery can't find the backup from the ID. Replace it with `quarantineFolderName: String?` set from `QuarantinedBackup.folderName`.

- [ ] **Step 1: Write the failing test.** In `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift`, replace the `fileStoreRoundTrip` test (lines 27–47) with the folder-name version:

```swift
    @Test("File store round-trips a populated journal")
    func fileStoreRoundTrip() throws {
        let url = Self.tempJournalURL()
        let store = FileMigrationJournalStore(url: url)
        let journal = MigrationJournal(
            state: .quarantining,
            operation: .replaceICloudWithLocal,
            startedAt: Date(timeIntervalSince1970: 100),
            lastHeartbeatAt: Date(timeIntervalSince1970: 105),
            previousMode: .iCloudSync,
            failureReason: nil,
            quarantineFolderName: "1700000000"
        )
        try store.write(journal)
        let restored = try store.read()
        #expect(restored.state == .quarantining)
        #expect(restored.operation == .replaceICloudWithLocal)
        #expect(restored.quarantineFolderName == "1700000000")
        #expect(restored.previousMode == .iCloudSync)
    }
```

- [ ] **Step 2: Run the test, expect failure.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationJournalTests 2>&1 | tail -12
```

Expected: compile failure — `incorrect argument label in call (have 'quarantineFolderName:', expected 'quarantineBackupID:')` and `value of type 'MigrationJournal' has no member 'quarantineFolderName'`.

- [ ] **Step 3: Rename the field with a back-compat decode.** In `MigrationJournal.swift`, change the property declaration (lines 58–60) from:

```swift
    /// Identifier of the quarantined backup (created during
    /// `.quarantining`) so the recovery flow knows which archive to
    /// restore.
    public var quarantineBackupID: UUID?
```

to:

```swift
    /// On-disk folder name (under `<root>/Quarantine/`) of the backup
    /// created during `.quarantining`, so the recovery flow can restore
    /// the *exact* archive (sync-7). Replaced the prior opaque
    /// `quarantineBackupID: UUID` which was never tied to the folder.
    public var quarantineFolderName: String?
```

In the `init` (lines 62–78), change the parameter (line 69) from `quarantineBackupID: UUID? = nil` to `quarantineFolderName: String? = nil`, and the assignment (line 77) from `self.quarantineBackupID = quarantineBackupID` to `self.quarantineFolderName = quarantineFolderName`. Then add a custom `init(from:)` so a stale on-disk journal written by the old build (carrying `quarantineBackupID`) still decodes — add it right after the memberwise `init` closing brace (after line 78):

```swift
    private enum CodingKeys: String, CodingKey {
        case state, operation, startedAt, lastHeartbeatAt
        case previousMode, failureReason
        case quarantineFolderName
        // Legacy key from the pre-hardening build; decoded but ignored
        // (the UUID was never tied to a folder, so it can't drive a
        // restore — recovery falls back to latestQuarantinedStore).
        case quarantineBackupID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try c.decode(State.self, forKey: .state)
        self.operation = try c.decodeIfPresent(ModeTransitionOp.self, forKey: .operation)
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.lastHeartbeatAt = try c.decodeIfPresent(Date.self, forKey: .lastHeartbeatAt)
        self.previousMode = try c.decodeIfPresent(SyncMode.self, forKey: .previousMode)
        self.failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
        self.quarantineFolderName = try c.decodeIfPresent(String.self, forKey: .quarantineFolderName)
    }
```

The synthesized `encode(to:)` keys off `CodingKeys`; because `quarantineBackupID` has no stored property, it is simply never encoded — clean forward writes, tolerant back-reads.

- [ ] **Step 4: Run the test, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationJournalTests 2>&1 | tail -12
```

Expected: `Test Suite 'MigrationJournal + MigrationJournalStore' passed` (all 7 tests). The package will still fail to *build* the coordinator until Task 6 updates the `quarantineBackupID = UUID()` callsite — run the full build to confirm the only remaining break is there:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | grep -A2 "quarantineBackupID\|error:" | head -10
```

Expected: errors only at `MigrationCoordinator.swift:169-170` referencing `quarantineBackupID` — fixed in Task 6.

- [ ] **Step 5: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationJournal.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationJournalTests.swift && git commit -m "refactor(sync): journal records quarantine folder name not opaque UUID (sync-7)"
```

---

## Task 6: Reorder `runMigration` — remove store before file move, copy-not-move, non-empty precondition (persist-3, sync-7)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (the `runMigration` quarantine + reconfigure ordering, lines 142–225; add an injected store-emptiness check seam)

The current order (MigrationCoordinator.swift): quarantine the live file (move, lines 168–173) → erase CloudKit → `reconfigure` (which removes+re-adds the store, line 194). persist-3 is that the *file is moved before the store connection is closed*. Fix: (a) reconfigure the store **before** capturing the backup so the SQLite connection to the *old* file is closed, then copy; (b) precondition a non-empty local store before the irreversible `replaceICloudWithLocal` erase; (c) record the folder name in the journal.

Because the coordinator already calls `host.reconfigure` (which now transactionally swaps and, on the new on-disk store, leaves the *old* file in place after the coordinator drops it), the safe recipe is: cancel notifications → write journal → (for `replaceICloudWithLocal`) precondition non-empty → reconfigure the store (closes the old connection) → copy the now-closed old file as the backup → erase CloudKit → settle → finalize. We surface store emptiness through an injected closure so the executing tests in Task 7 can drive it.

- [ ] **Step 1: Add a store-row-count seam to the coordinator init.** In `MigrationCoordinator.swift`, add a stored property after `cloudKitContainerIdentifier` (line 43):

```swift
    /// Returns the current count of user-visible task rows in the live
    /// store. Used to precondition a non-empty local store before the
    /// irreversible `replaceICloudWithLocal` erase. Injected so the
    /// executing tests can drive empty/non-empty without a live store.
    private let localStoreRowCount: @Sendable () async -> Int
```

Add a matching `init` parameter — change the `init` signature's tail (lines 55–56) from:

```swift
        breadcrumbs: BreadcrumbBuffer? = nil,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier
    ) {
```

to:

```swift
        breadcrumbs: BreadcrumbBuffer? = nil,
        cloudKitContainerIdentifier: String = StoreConfiguration.defaultCloudKitContainerIdentifier,
        localStoreRowCount: @escaping @Sendable () async -> Int = { 1 }
    ) {
```

and add the assignment at the end of the `init` body, after `self.cloudKitContainerIdentifier = cloudKitContainerIdentifier` (line 66):

```swift
        self.localStoreRowCount = localStoreRowCount
```

The default `{ 1 }` keeps existing callers (`AppEnvironment`, existing tests) compiling unchanged while defaulting to "non-empty" — production should pass a real counter, captured in Step 4's follow-on note, but the default never *blocks* a legitimate migration. (DRY/YAGNI: we don't fetch the count eagerly; the closure is only invoked on the `replaceICloudWithLocal` branch.)

- [ ] **Step 2: Write the failing executing test.** This test belongs to Task 7's new file, but we author the precondition assertion here so Step 3 has a Red target. Create the new file `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift` with just the precondition test for now (Task 7 adds the rest):

```swift
import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("MigrationCoordinator runner (executing, no live store)", .serialized)
struct MigrationRunnerExecutingTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigRunner-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeCoordinator(
        startMode: SyncMode,
        rowCount: @escaping @Sendable () async -> Int = { 1 },
        journal: InMemoryMigrationJournalStore = InMemoryMigrationJournalStore(),
        eraser: FakeCloudKitZoneEraser = FakeCloudKitZoneEraser()
    ) -> (MigrationCoordinator, FakePersistenceReconfigurer, InMemoryMigrationJournalStore, FakeCloudKitZoneEraser, URL) {
        let dir = tempDir()
        let recon = FakePersistenceReconfigurer(initialMode: startMode)
        let suite = "MigRunner-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: dir),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: rowCount
        )
        return (coordinator, recon, journal, eraser, dir)
    }

    @Test("replaceICloudWithLocal on an empty local store throws before erasing")
    @MainActor
    func emptyStorePreconditionBlocksErase() async throws {
        let (coordinator, _, journal, eraser, dir) = makeCoordinator(startMode: .localOnly, rowCount: { 0 })
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // The eraser must NOT have been called — we bailed before the
        // irreversible step.
        #expect(await eraser.callCount == 0)
        // Journal is left .failed for the recovery sheet.
        #expect(try journal.read().state == .failed)
    }
}
```

- [ ] **Step 3: Run the test, expect failure.** It will fail to compile because `FakePersistenceReconfigurer` doesn't exist yet (created in Task 7 Step 1) — so create that fake first as part of this step. Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/FakePersistenceReconfigurer.swift`:

```swift
import Foundation
@testable import LillistCore

/// In-memory `PersistenceReconfiguring` fake. Records the ordered
/// sequence of modes it was reconfigured to so executing tests can
/// assert phase ordering without a live `NSPersistentCloudKitContainer`.
/// Optionally throws on the Nth `reconfigure` to inject a failed swap.
actor FakePersistenceReconfigurer: PersistenceReconfiguring {
    private(set) var mode: SyncMode
    private(set) var reconfigureCalls: [SyncMode] = []
    private var failOnCall: Int?

    init(initialMode: SyncMode) {
        self.mode = initialMode
    }

    var currentMode: SyncMode { mode }

    /// Arm a throw on the Nth (1-based) `reconfigure` call.
    func failOnReconfigure(call n: Int) {
        failOnCall = n
    }

    func reconfigure(to newMode: SyncMode) async throws {
        reconfigureCalls.append(newMode)
        if let failOnCall, reconfigureCalls.count == failOnCall {
            throw LillistError.storeUnavailable(reason: "fake reconfigure failure on call \(failOnCall)")
        }
        mode = newMode
    }
}
```

Now run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationRunnerExecutingTests 2>&1 | tail -15
```

Expected: the test runs but **fails** the assertion — the current `runMigration` does not precondition store emptiness, so `beginEnable` does not throw before the eraser runs (`eraser.callCount` would be 1, and the journal would be `.idle`). This is the Red state. (If it instead errors on `localStoreRowCount`, Step 1 wasn't applied — re-check.)

- [ ] **Step 4: Reorder `runMigration` and add the precondition.** Replace the entire `runMigration` method body (lines 142–225) with the reordered, copy-not-move, preconditioned version:

```swift
    private func runMigration(op: ModeTransitionOp, targetMode: SyncMode, storeURL: URL) async throws {
        breadcrumb("sync mode change start \(op.rawValue)")
        // 1. preparing — cancel notifications first so a destructive
        //    op doesn't leave stale fires pointing at deleted rows
        //    (skeptic G9). cancelAllPending MUST precede any
        //    destructive step.
        emit(.preparing)
        if let scheduler = notificationScheduler {
            await scheduler.cancelAllPending()
        }

        // 2. journal: starting
        var entry = MigrationJournal(
            state: .preparing,
            operation: op,
            startedAt: Date(),
            lastHeartbeatAt: Date(),
            previousMode: await host.currentMode
        )
        try journal.write(entry)

        do {
            // 3. precondition: an irreversible erase must not run
            //    against an empty local store (sync-7). If the user has
            //    no local data, "replace iCloud with local" would wipe
            //    iCloud and leave them with nothing.
            if op == .replaceICloudWithLocal {
                let rows = await localStoreRowCount()
                guard rows > 0 else {
                    throw LillistError.storeUnavailable(
                        reason: "Refusing to replace iCloud with an empty local store"
                    )
                }
            }

            // 4. structural swap FIRST so the SQLite connection to the
            //    old file is closed before we touch the file on disk
            //    (persist-3). PersistenceHost.reconfigure removes the
            //    old store from the coordinator (closing the
            //    connection) and re-adds a fresh description; the old
            //    on-disk file is left intact for the copy below.
            entry.state = .reconfiguringStore
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.reconfiguringStore)
            try await host.reconfigure(to: targetMode)
            await syncModeStore.setMode(targetMode)

            // 5. quarantine the now-closed old store as a recovery
            //    anchor — COPY, not move, and only if the file is still
            //    present. Record the exact folder name in the journal.
            emit(.backingUp)
            entry.state = .quarantining
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let backup = try quarantine.copyStore(at: storeURL)
                entry.quarantineFolderName = backup.folderName
                try journal.write(entry)
            }

            // 6. cloudkit-side mutation (only for replaceICloudWithLocal).
            if op == .replaceICloudWithLocal {
                entry.state = .mutatingCloudKit
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(.erasingICloud(progress: 0))
                _ = try await zoneEraser.eraseManagedZones(
                    in: cloudKitContainerIdentifier,
                    progress: { [weak self] fraction in
                        await MainActor.run { self?.emit(.erasingICloud(progress: fraction)) }
                    }
                )
            }

            // 7. wait for CloudKit to settle (only when going to
            //    iCloudSync; LocalOnly has nothing to wait on).
            if targetMode == .iCloudSync {
                entry.state = .awaitingSync
                entry.lastHeartbeatAt = Date()
                try journal.write(entry)
                emit(op == .replaceICloudWithLocal ? .uploading(progress: nil) : .downloading(progress: nil))
                _ = await quiesceMonitor.waitForQuiesce(minQuietWindow: 5, hardTimeout: 300)
            }

            // 8. finalize.
            entry.state = .finalizing
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            emit(.finalizing)

            try journal.clear()
            emit(.completed)
            breadcrumb("sync mode change completed \(op.rawValue)")
        } catch {
            entry.state = .failed
            entry.failureReason = "\(error)"
            entry.lastHeartbeatAt = Date()
            try? journal.write(entry)
            emit(.failed(reason: "\(error)"))
            breadcrumb("sync mode change failed \(op.rawValue)", success: false)
            throw error
        }
    }
```

Note: this also fixes the build break from Task 5 (`quarantineBackupID` is gone). The `replaceICloudWithLocal` precondition runs *before* the reconfigure so we never even close the iCloud store when the local store is empty.

- [ ] **Step 5: Run the test, expect pass; then commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore 2>&1 | tail -3 && swift test --package-path Packages/LillistCore --filter MigrationRunnerExecutingTests 2>&1 | tail -10
```

Expected: `Build complete!` and `emptyStorePreconditionBlocksErase` passes (eraser `callCount == 0`, journal `.failed`). Commit:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/FakePersistenceReconfigurer.swift && git commit -m "fix(sync): remove store before quarantine-by-copy; precondition non-empty local store (persist-3, sync-7)"
```

---

## Task 7: Executing state-machine tests — phase order, journal transitions, eraser callCount, cancel ordering (sync-1, test-1)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift` (add the phase-order + transition + cancel-ordering tests + a progress collector + a recording notification scheduler)

These tests prove the state machine actually executes under `swift test` (sync-1) — closing the "silently skips → false green" gap (test-1). We collect emitted `MigrationPhase` values, assert the exact ordered journal-state sequence, assert eraser `callCount` (0 for `disableNow`, 1 for `replaceICloudWithLocal`), and assert `cancelAllPending` fires before any destructive step.

First confirm whether `NotificationScheduler` can be faked cheaply — check the type's shape.

- [ ] **Step 1: Inspect `NotificationScheduler` to build a recording fake.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "class NotificationScheduler\|func cancelAllPending\|public init" Packages/LillistCore/Sources/LillistCore/Notifications/NotificationScheduler.swift | head -20
```

Read the result. If `cancelAllPending()` is a method on a `final class`/`actor` with a constructible `init` accepting a `UNUserNotificationCenter`-like seam, capture a recording flag by wrapping it. If it is not cheaply fakeable, drive the cancel-ordering assertion through a **side channel**: the coordinator emits `.preparing` first and only then any destructive phase, so asserting `.preparing` precedes `.reconfiguringStore`/`.erasingICloud` in the collected phase stream proves the ordering. Use this phase-stream approach (no scheduler needed — the existing tests pass `notificationScheduler: nil`), which is the simplest correct assertion (YAGNI).

- [ ] **Step 2: Write the phase-order and journal-transition tests.** Append to `MigrationRunnerExecutingTests.swift` (inside the struct, after `emptyStorePreconditionBlocksErase`). Add a phase collector helper and the tests:

```swift
    /// Collects emitted phases from a coordinator's progressStream
    /// until the stream sees `.completed` or `.failed`.
    @MainActor
    private func collectPhases(
        from coordinator: MigrationCoordinator,
        whileRunning body: @escaping @MainActor () async throws -> Void
    ) async rethrows -> [MigrationPhase] {
        let stream = coordinator.progressStream
        let collector = PhaseCollector()
        let consumer = Task {
            for await phase in stream {
                await collector.append(phase)
                if case .completed = phase { break }
                if case .failed = phase { break }
            }
        }
        defer { consumer.cancel() }
        try await body()
        // Give the consumer a moment to drain the terminal event.
        try? await Task.sleep(nanoseconds: 50_000_000)
        return await collector.values
    }

    @Test("disableNow: phases ordered, journal cleared, eraser NOT called")
    @MainActor
    func disableNowExecutes() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .iCloudSync)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        let phases = try await collectPhases(from: coordinator) {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }

        // Eraser must not run on a disable.
        #expect(await eraser.callCount == 0)
        // Mode swapped to localOnly exactly once.
        #expect(await recon.reconfigureCalls == [.localOnly])
        // Journal cleared (idle) on success.
        #expect(try journal.read() == .idle)
        // preparing must precede the structural swap.
        let preparingIdx = phases.firstIndex(of: .preparing)
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        #expect(preparingIdx != nil && reconfigIdx != nil)
        #expect(preparingIdx! < reconfigIdx!)
        // Terminal phase is completed.
        #expect(phases.last == .completed)
    }

    @Test("replaceICloudWithLocal: eraser called once, after reconfigure, cancel-before-destructive")
    @MainActor
    func replaceICloudWithLocalExecutes() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .localOnly, rowCount: { 5 })
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        let phases = try await collectPhases(from: coordinator) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }

        #expect(await eraser.callCount == 1)
        #expect(await recon.reconfigureCalls == [.iCloudSync])
        #expect(try journal.read() == .idle)
        // preparing precedes both the swap and the erase (cancel
        // notifications happen in .preparing, before any destructive
        // step).
        let preparingIdx = phases.firstIndex(of: .preparing)
        let reconfigIdx = phases.firstIndex(of: .reconfiguringStore)
        let eraseIdx = phases.firstIndex { if case .erasingICloud = $0 { return true } else { return false } }
        #expect(preparingIdx != nil && reconfigIdx != nil && eraseIdx != nil)
        #expect(preparingIdx! < reconfigIdx!)
        #expect(reconfigIdx! < eraseIdx!)
    }
```

Add the `PhaseCollector` actor at file scope (after the closing brace of the `MigrationRunnerExecutingTests` struct):

```swift
/// Thread-safe ordered sink for emitted migration phases.
actor PhaseCollector {
    private(set) var values: [MigrationPhase] = []
    func append(_ phase: MigrationPhase) { values.append(phase) }
}
```

- [ ] **Step 3: Run the tests, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationRunnerExecutingTests 2>&1 | tail -15
```

Expected: 3 tests pass (`emptyStorePreconditionBlocksErase`, `disableNowExecutes`, `replaceICloudWithLocalExecutes`). These run end-to-end under plain `swift test` — no `liveSwapAllowed` gate — proving sync-1/test-1 are closed for the state machine itself.

- [ ] **Step 4: Add the failure-injection test.** Append one more test to the struct asserting that a failed reconfigure leaves `.failed` with the right `previousMode`, rethrows, and records `success: false`:

```swift
    @Test("Reconfigure failure leaves .failed journal with previousMode and rethrows")
    @MainActor
    func reconfigureFailureLeavesFailedJournal() async throws {
        let (coordinator, recon, journal, eraser, dir) = makeCoordinator(startMode: .iCloudSync)
        await recon.failOnReconfigure(call: 1)
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)

        await #expect(throws: LillistError.self) {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
        }
        let j = try journal.read()
        #expect(j.state == .failed)
        #expect(j.previousMode == .iCloudSync)
        #expect(j.failureReason?.isEmpty == false)
        // The reconfigure was attempted but threw; the eraser never ran
        // (disable doesn't erase) and the mode stayed put.
        #expect(await eraser.callCount == 0)
        #expect(await recon.mode == .iCloudSync)
    }
```

- [ ] **Step 5: Run + commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationRunnerExecutingTests 2>&1 | tail -12
```

Expected: 4 tests pass. Commit:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift && git commit -m "test(sync): executing state-machine coverage — phase order, journal transitions, eraser callCount (sync-1, test-1)"
```

---

## Task 8: Failure injection across phases + secondary-catch-write masking + ungated restore tests (sync-3, test-2)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/ThrowingMigrationJournalStore.swift`
- Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRecoveryTests.swift`

sync-3 wants the `.failed` path exercised with a throwing journal store decorator (so a secondary catch-write failure doesn't mask the original error), and per-phase failure injection. test-2 wants ungated `restoreFromBackup` coverage (happy path + missing-backup `storeUnavailable`).

- [ ] **Step 1: Write the throwing journal decorator.** Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/ThrowingMigrationJournalStore.swift`:

```swift
import Foundation
@testable import LillistCore

/// Decorator over a `MigrationJournalStore` that throws on the Nth
/// `write` so tests can prove the coordinator's secondary catch-write
/// failure does not mask the *original* error (sync-3).
final class ThrowingMigrationJournalStore: MigrationJournalStore, @unchecked Sendable {
    private let underlying: MigrationJournalStore
    private let lock = NSLock()
    private var writeCount = 0
    private let throwOnWrite: Int

    /// - Parameter throwOnWrite: 1-based index of the `write` call that
    ///   should throw. Use `Int.max` to never throw.
    init(underlying: MigrationJournalStore, throwOnWrite: Int) {
        self.underlying = underlying
        self.throwOnWrite = throwOnWrite
    }

    func read() throws -> MigrationJournal { try underlying.read() }

    func write(_ journal: MigrationJournal) throws {
        lock.lock()
        writeCount += 1
        let shouldThrow = writeCount == throwOnWrite
        lock.unlock()
        if shouldThrow {
            throw LillistError.storeUnavailable(reason: "journal write \(throwOnWrite) failed (test)")
        }
        try underlying.write(journal)
    }

    func clear() throws { try underlying.clear() }
}
```

- [ ] **Step 2: Write the failing recovery + masking tests.** Create `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRecoveryTests.swift`:

```swift
import Testing
import Foundation
import CloudKit
@testable import LillistCore

@Suite("MigrationCoordinator recovery + failure injection (executing)", .serialized)
struct MigrationRecoveryTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigRecovery-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    private func makeCoordinator(
        startMode: SyncMode,
        journal: MigrationJournalStore,
        quarantineRoot: URL
    ) -> (MigrationCoordinator, FakePersistenceReconfigurer, FakeCloudKitZoneEraser) {
        let recon = FakePersistenceReconfigurer(initialMode: startMode)
        let eraser = FakeCloudKitZoneEraser()
        let suite = "MigRecovery-\(UUID().uuidString)"
        let modeStore = SyncModeStore(suiteName: suite)
        let coordinator = MigrationCoordinator(
            host: recon,
            journal: journal,
            quarantine: QuarantineManager(rootDirectory: quarantineRoot),
            zoneEraser: eraser,
            quiesceMonitor: SyncQuiesceMonitor(bridge: CloudKitEventBridge()),
            notificationScheduler: nil,
            syncModeStore: modeStore,
            localStoreRowCount: { 1 }
        )
        return (coordinator, recon, eraser)
    }

    @Test("restoreFromBackup restores contents, reverts mode, clears journal")
    @MainActor
    func restoreHappyPath() async throws {
        let dir = tempDir()
        // Seed a quarantined backup via copyStore.
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("backup-content".utf8).write(to: liveURL)
        let quarantine = QuarantineManager(rootDirectory: dir)
        _ = try quarantine.copyStore(at: liveURL)
        // Wipe the live store to simulate a crashed, half-swapped state.
        try FileManager.default.removeItem(at: liveURL)

        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(
            state: .reconfiguringStore,
            operation: .replaceICloudWithLocal,
            previousMode: .iCloudSync
        ))
        let (coordinator, recon, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)

        #expect(try String(contentsOf: liveURL, encoding: .utf8) == "backup-content")
        #expect(await recon.mode == .iCloudSync)   // reverted to previousMode
        #expect(try journal.read() == .idle)        // cleared
    }

    @Test("restoreFromBackup with no backup throws storeUnavailable")
    @MainActor
    func restoreNoBackupThrows() async throws {
        let dir = tempDir()
        let liveURL = dir.appendingPathComponent("Lillist.sqlite")
        let journal = InMemoryMigrationJournalStore(initial: MigrationJournal(state: .failed, previousMode: .iCloudSync))
        let (coordinator, _, _) = makeCoordinator(startMode: .localOnly, journal: journal, quarantineRoot: dir)

        await #expect(throws: LillistError.self) {
            try await coordinator.restoreFromBackup(filename: "Lillist.sqlite", targetURL: liveURL)
        }
    }

    @Test("A secondary journal-write failure in the catch does not mask the original error")
    @MainActor
    func secondaryWriteFailureDoesNotMask() async throws {
        let dir = tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        try Data("x".utf8).write(to: storeURL)
        // The reconfigure throws (call 1). The catch then attempts to
        // write the .failed journal — make that write throw too. The
        // ORIGINAL reconfigure error must still propagate.
        let inner = InMemoryMigrationJournalStore()
        // write sequence under disableNow: 1=preparing, 2=reconfiguring,
        // then reconfigure throws → catch write is the 3rd write.
        let journal = ThrowingMigrationJournalStore(underlying: inner, throwOnWrite: 3)
        let (coordinator, recon, _) = makeCoordinator(startMode: .iCloudSync, journal: journal, quarantineRoot: dir)
        await recon.failOnReconfigure(call: 1)

        do {
            try await coordinator.beginDisable(strategy: .now, storeURL: storeURL)
            Issue.record("expected beginDisable to throw")
        } catch let error as LillistError {
            // The original reconfigure failure, not the catch-write
            // failure, surfaces. Both are storeUnavailable here, so we
            // assert the reason carries the reconfigure message.
            if case .storeUnavailable(let reason) = error {
                #expect(reason.contains("fake reconfigure failure"))
            } else {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
```

- [ ] **Step 3: Run the tests, expect pass.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationRecoveryTests 2>&1 | tail -15
```

Expected: 3 tests pass. The `secondaryWriteFailureDoesNotMask` test confirms the coordinator's `catch` uses `try? journal.write(entry)` (MigrationCoordinator.swift:220 — note `try?`, which swallows the secondary write error) and then `throw error` rethrows the *original* reconfigure error — exactly the non-masking contract sync-3 requires. If it fails because the catch uses `try` (not `try?`), that is a real defect: fix it by ensuring the catch block writes with `try?` so the secondary failure can't shadow the original (the current code already does this — verify).

- [ ] **Step 4: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/Sync/ThrowingMigrationJournalStore.swift Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRecoveryTests.swift && git commit -m "test(sync): failure injection + ungated restoreFromBackup coverage (sync-3, test-2)"
```

---

## Task 9: App-hosted iOS unit-test target + `liveSwapAllowed` meta-test (test-1)

**Files:**
- Create `Apps/Lillist-iOS/Tests/AppHostedTests/LiveSwapHostMetaTests.swift`
- Modify `Apps/Lillist-iOS/project.yml` (add `Lillist-iOSAppHostedTests` target + scheme wiring)
- Modify `CLAUDE.md` (document the command + rationale)

The existing `Lillist-iOSTests` bundle runs with `TEST_HOST: ""` / `BUNDLE_LOADER: ""` — so it has no real `CFBundleIdentifier`, which is *why* `liveSwapAllowed` is false even under xcodebuild and the live-container swap tests silently skip (test-1). We add a second iOS test target that **is** hosted by the `Lillist-iOS` app (real bundle ID), wire `LillistCore`'s gated tests to run there, and add a meta-test that *fails* if `liveSwapAllowed` is false under that host — so a misconfigured host can't masquerade as green.

- [ ] **Step 1: Write the meta-test.** Create `Apps/Lillist-iOS/Tests/AppHostedTests/LiveSwapHostMetaTests.swift`:

```swift
import Testing
import Foundation

/// Meta-test: this target exists *specifically* to run the live-store
/// swap tests under a real app host. Those tests gate themselves on
/// `Bundle.main.bundleIdentifier?.isEmpty == false` (a.k.a.
/// `liveSwapAllowed`). If the host is ever misconfigured back to a
/// `TEST_HOST=""` standalone bundle, that gate silently turns the
/// safety-critical swap tests into no-ops that "pass". This test fails
/// loudly in that case so the regression can't ship green (test-1).
@Suite("Live swap host configuration")
struct LiveSwapHostMetaTests {
    @Test("This target runs inside a real app host (non-empty bundle identifier)")
    func bundleIdentifierIsPresent() {
        let bundleID = Bundle.main.bundleIdentifier
        #expect(bundleID?.isEmpty == false,
                "Live-swap tests require an app-hosted target. Bundle.main.bundleIdentifier was \(bundleID ?? "nil"). The Lillist-iOSAppHostedTests target must keep TEST_HOST pointed at Lillist-iOS.")
    }
}
```

- [ ] **Step 2: Add the app-hosted test target to `project.yml`.** In `Apps/Lillist-iOS/project.yml`, add a new target after the `Lillist-iOSUITests` target block (before the `schemes:` key). The target hosts inside the app and co-compiles the gated `LillistCore` swap tests so they execute with a real bundle ID:

```yaml
  # App-hosted unit-test target (test-1). Unlike Lillist-iOSTests
  # (TEST_HOST=""), this bundle is hosted by Lillist-iOS, so
  # Bundle.main.bundleIdentifier is the app's real ID and the
  # liveSwapAllowed-gated migration/swap tests actually execute
  # instead of silently skipping. Co-compiles the gated LillistCore
  # test sources directly (they @testable-import LillistCore, which
  # the host app links).
  Lillist-iOSAppHostedTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: Tests/AppHostedTests
      - path: ../../Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift
      - path: ../../Packages/LillistCore/Tests/LillistCoreTests/Sync/CloudKitZoneEraserTests.swift
      - path: ../../Packages/LillistCore/Tests/LillistCoreTests/Sync/FakePersistenceReconfigurer.swift
      - path: ../../Packages/LillistCore/Tests/LillistCoreTests/Persistence/PersistenceHostTests.swift
      - path: ../../Packages/LillistCore/Tests/LillistCoreTests/Persistence/StoreLevelModeSwapSpike.swift
    dependencies:
      - package: LillistCore
        product: LillistCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: io.mikeydotio.Lillist.appHostedTests
        IPHONEOS_DEPLOYMENT_TARGET: "26.0"
        TARGETED_DEVICE_FAMILY: "1,2"
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Lillist.app/Lillist"
        BUNDLE_LOADER: "$(TEST_HOST)"
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Automatic
```

Then add it to the `Lillist-iOS` scheme. Under `schemes: → Lillist-iOS: → build: → targets:`, add the line `Lillist-iOSAppHostedTests: [test]` after `Lillist-iOSUITests: [test]`, and under `schemes: → Lillist-iOS: → test: → targets:` add `- Lillist-iOSAppHostedTests` after `- Lillist-iOSUITests`. The resulting blocks read:

```yaml
    build:
      targets:
        Lillist-iOS: all
        ShareExtension-iOS: all
        ShortcutsActions: all
        Lillist-iOSTests: [test]
        Lillist-iOSUITests: [test]
        Lillist-iOSAppHostedTests: [test]
```

and

```yaml
    test:
      config: Debug
      targets:
        - Lillist-iOSTests
        - Lillist-iOSUITests
        - Lillist-iOSAppHostedTests
        - package: LillistUI/LillistUITests
```

- [ ] **Step 3: Regenerate the pbxproj.** Per CLAUDE.md, after changing `project.yml` regenerate both projects:

```bash
cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project . && cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
```

Expected: `Generated project at ...` for both, no errors. Verify the new target exists:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -c "Lillist-iOSAppHostedTests" Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj
```

Expected: a count ≥ 1.

- [ ] **Step 4: Run the app-hosted suite, expect the gated tests to EXECUTE (not skip).** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:Lillist-iOSAppHostedTests 2>&1 | tail -40
```

Expected: `LiveSwapHostMetaTests` passes (bundle ID present); `PersistenceHostTests.failedReconfigureRollsBack`, `reconfigureSwapsAndPreservesData`, `MigrationCoordinatorTests.disableNow`, `MigrationCoordinatorTests.replaceICloudWithLocal`, and the `StoreLevelModeSwapSpike` live tests now **run** (not skipped) and pass — because `liveSwapAllowed` is now true. `** TEST SUCCEEDED **` at the end.

- [ ] **Step 5: Document in CLAUDE.md and commit.** In `CLAUDE.md`, under the `## Build & test` section, after the iOS-only tests `xcodebuild` block, add this note. First read the exact surrounding text:

```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "iOS-only tests\|Lillist-iOSAppHostedTests\|liveSwapAllowed" CLAUDE.md
```

Then insert (via Edit) immediately after the existing iOS xcodebuild test fenced block in `## Build & test`:

```markdown
The **migration/store-swap tests are app-hosted**: `MigrationCoordinatorTests`,
`PersistenceHostTests`, and `StoreLevelModeSwapSpike` gate their
live-container cases on a real `CFBundleIdentifier` (`liveSwapAllowed`),
which the standalone `LillistCoreTests` SPM bundle and the
`TEST_HOST=""` `Lillist-iOSTests` bundle both lack — so those cases
*silently skip* under `swift test`. The `Lillist-iOSAppHostedTests`
target hosts them inside `Lillist-iOS` (real bundle ID) so they
actually execute; `LiveSwapHostMetaTests` fails loudly if the host is
ever misconfigured back to standalone. Run them with:

\`\`\`bash
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:Lillist-iOSAppHostedTests
\`\`\`

The fully-executing state-machine tests (`MigrationRunnerExecutingTests`,
`MigrationRecoveryTests`) run under plain `swift test` because they use
the `PersistenceReconfiguring` fake instead of a live container.
```

(Replace the escaped `\`\`\`` fences with real triple-backticks when editing — the escape here is only to keep this plan's fence from closing early.) Commit:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Tests/AppHostedTests/LiveSwapHostMetaTests.swift Apps/Lillist-iOS/project.yml Apps/Lillist-iOS/Lillist-iOS.xcodeproj/project.pbxproj Apps/Lillist-macOS.xcodeproj/project.pbxproj CLAUDE.md && git commit -m "test(sync): app-hosted test target so live-swap tests execute + meta-test (test-1)"
```

(If `git status` shows the macOS pbxproj was *not* changed by the regenerate — it usually won't be, since only the iOS spec changed — drop that path from the `git add`.)

---

## Task 10: Update the gated `MigrationCoordinatorTests` for the new initializer + full-suite green

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift` (the live tests now exercise the reordered runner; they keep their `liveSwapAllowed` gate but must seed a non-empty store)

The reordered `runMigration` now preconditions a non-empty local store for `replaceICloudWithLocal` and copies the store *after* reconfigure. The existing gated `replaceICloudWithLocal` test (line 81) uses the default `localStoreRowCount` (`{ 1 }`, non-empty) so it still passes, but we make it explicit and add a seed file so the copy step has something to copy. The `disableNow` test is unaffected.

- [ ] **Step 1: Seed a store file in both live tests so the copy step runs.** In `MigrationCoordinatorTests.swift`, in `disableNow` (after line 48, before `beginDisable`) add a seed write:

```swift
        try Data("seed".utf8).write(to: storeURL)
```

and in `replaceICloudWithLocal` (after line 80's coordinator construction, before `beginEnable` on line 81) add:

```swift
        try Data("seed".utf8).write(to: storeURL)
```

No assertion changes are needed — both tests already assert `journal.read() == .idle` and the correct `callCount`, which the reordered runner still satisfies.

- [ ] **Step 2: Run the package suite, expect green (gated tests skip under SPM).** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -20
```

Expected: full `LillistCore` suite passes; the `liveSwapAllowed`-gated tests skip under swift test, every new executing test (`MigrationRunnerExecutingTests`, `MigrationRecoveryTests`, `QuarantineRestoreTests`) passes, and the existing 649 tests stay green. No warnings.

- [ ] **Step 3: Run the app-hosted suite once more for the end-to-end gated proof.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' -only-testing:Lillist-iOSAppHostedTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **` with the gated live tests executing (the reordered runner + transactional swap verified end-to-end against a real container).

- [ ] **Step 4: Commit.** Run:

```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift && git commit -m "test(sync): seed store in gated migration tests for the reordered copy step"
```

---

## Self-review checklist

Confirm each finding is closed by a named task before marking the plan done:

- [ ] **persist-3** (live SQLite file moved out from under the open container) — Task 4 adds `copyStore` (copy-not-move) and Task 6 reorders `runMigration` so `host.reconfigure` removes/closes the store *before* the file is copied. Verified by `MigrationRunnerExecutingTests` (no file yanked while open) and the app-hosted `StoreLevelModeSwapSpike`/`PersistenceHostTests`.
- [ ] **sync-1** (state machine has zero executing coverage under `swift test`) — Task 7's `MigrationRunnerExecutingTests` run end-to-end under plain `swift test` via the `PersistenceReconfiguring` fake (Tasks 1, 6), asserting phase order, journal transitions, eraser callCount.
- [ ] **sync-3** (no failure injection; `.failed` path, partial rollback, error propagation never exercised) — Task 8's `ThrowingMigrationJournalStore` + `FakePersistenceReconfigurer.failOnReconfigure` drive `.failed` journal with `previousMode`, rethrow, and the secondary-catch-write-doesn't-mask-original assertion.
- [ ] **sync-4** (partial reconfigure failure leaves a store-less coordinator with no rollback) — Task 3 makes `flushAndSwap` transactional: capture the *original mode's description* (rebuilt via `PersistenceController.makeStoreDescription`, which carries `cloudKitContainerOptions`), do/catch, re-add the original via the description-taking `addPersistentStore(with:completionHandler:)` on add-failure, `storeUnavailable` if rollback also throws. Verified by `PersistenceHostTests.failedReconfigureRollsBack` (app-hosted).
- [ ] **Roadmap #1** (rollback must preserve `cloudKitContainerOptions` — a half-added iCloud store must roll back to a *mirroring* store, not a plain local one) — Task 3 rebuilds the rollback description from the captured original `SyncMode` and re-adds via the description API (the `(type:configuration:at:options:)` overload provably drops CloudKit options; the live `store.options` doesn't surface them — `StoreLevelModeSwapSpike.swapMutatesDescription`). Verified by the ungated `PersistenceHostTests.rollbackPreservesCloudKitOptions`, which asserts the captured `lastRollbackDescription.cloudKitContainerOptions` is non-nil, matches `defaultCloudKitContainerIdentifier`, and is `.private` scope. (True live-store assertion is unreachable — the framework doesn't expose CloudKit options back through `NSPersistentStore` — so the assertion targets the value object the rollback re-adds; stated explicitly in the test.)
- [ ] **sync-7** (journal `quarantineBackupID` not tied to the on-disk folder; no non-empty precondition) — Task 5 renames the field to `quarantineFolderName` set from `QuarantinedBackup.folderName`; Task 6 adds the non-empty `localStoreRowCount` precondition before the `replaceICloudWithLocal` erase. Verified by `QuarantineRestoreTests` + `emptyStorePreconditionBlocksErase`.
- [ ] **conc-4** (remove+add not in one atomic main-queue critical section) — Task 3 wraps the flush + remove + add (+ rollback) inside a single `viewContext.perform`.
- [ ] **test-1** (Plan-21 swap & migration tests silently skip under every documented command → false green) — Task 9 adds the app-hosted `Lillist-iOSAppHostedTests` target (real `CFBundleIdentifier`) so the gated tests execute, plus `LiveSwapHostMetaTests` asserting `liveSwapAllowed == true` so a misconfigured host fails loudly.
- [ ] **test-2** (`restoreFromBackup` has zero test coverage) — Task 8's `MigrationRecoveryTests` cover the happy path (restores contents, reverts mode, clears journal) and the no-backup `storeUnavailable` path, both ungated under `swift test`.

**Strengths preserved (not refactored away):** the same `NSPersistentCloudKitContainer` instance lives the app's lifetime (no re-instantiation); the synchronous same-actor AsyncStream registration in `progressStream` is untouched; the static-factory `makeStoreDescription` contract is reused verbatim for both the forward swap and the rollback re-add (the rollback rebuilds the *original mode's* description through the same factory, which is what carries `cloudKitContainerOptions` back — no bespoke options-copying code); the clock-injected `QuarantineManager` gains `copyStore` without disturbing the existing `quarantineStore`/`cleanupExpired`/`restore` surface; the DTO boundary is unaffected (no `NSManagedObject` escapes — the new seam exposes only `SyncMode`).
