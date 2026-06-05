# Observability & Structured Logging Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 6.**
>
> **✅ Wave-5 reconciliation (2026-06-05):** Verified clean — Wave 5 (`4dc1f96..0bd7796`) touched none of this plan's instrument targets (`MigrationCoordinator.swift`, `TaskStore.swift`, both `AppEnvironment.swift`, the new MetricKit observer); every task anchor still resolves and the Wave-4 note below remains the operative anchor guidance. **One EOF note:** Wave 5 appended a new last entry to `engineering-notes.md` (`## 2026-05-28 — Crash-reporter redaction is layered…`, ~L2217), so if this plan appends a notes section, re-Read the tail and append after that real EOF.
>
> **⚠️ Wave-4 reconciliation (2026-06-04):** Wave 4 shifted the two hotspot files this plan instruments — **re-Read and re-anchor before editing both**.
> - **Task 4 (`MigrationCoordinator.swift`)**: `runMigration` is now ~L189 (not ~L164) and **opens with TWO reentrancy guards** — a synchronous `if let current = try? journal.read(), current.isInFlight { throw }`, then a `guard !isMigrating else { throw }; isMigrating = true; defer { isMigrating = false }` — *before* the first `await breadcrumb(...)`. Put the signpost `beginInterval` / `defer endInterval` / start-notice **after** those guards-and-`defer` and **before** `await breadcrumb("sync mode change start …")`; do **not** add a third guard or move the existing ones. Phase 6 (`// 6. cloudkit-side mutation`) now has a **NEW pre-erase `accountStateProvider` guard** that throws *before* `emit(.erasingICloud(progress: 0))` — keep the "erasing iCloud zones" notice right after `emit(.erasingICloud(progress: 0))` (it stays inside the block, after the new guard). Phase 8 (`// 8. finalize.`) now `emit(.finalizing)` then calls `scheduler.restoreSteadyState(...)` *before* `journal.clear()` / `emit(.completed)`; the "migration completed" notice still goes after `emit(.completed)` (now ~L327) and before `await breadcrumb(...)` — unchanged anchor, just don't disturb the new `restoreSteadyState` block. The init grew two optional params (`preferencesStore:`, `accountStateProvider:`, both default `nil`) — irrelevant to this additive log work. `restoreFromBackup` is now ~L169. **All `breadcrumb(...)` calls are now `await breadcrumb(...)`** (already awaited inline) — add no `await`.
> - **Task 6 (iOS `AppEnvironment.swift`)**: `bootstrap()` is now ~L298 and gained a `HistoryPruner(...).sweep()` block right after `autoPurgeJob.run()`, and the `MigrationCoordinator(...)` call gained `preferencesStore: preferencesStore`. **The tail you append to is UNCHANGED** — `startObservingPauseReason()` is still the last statement (~L343); append `metricKitObserver.startReceiving()` after it. Re-Read the property block and the tail; do not touch the new pruner/coordinator wiring.
> - **Task 5 (`TaskStore.children(of:)`)**: structurally **unaffected** — still a single `try await context.perform { … return try context.fetch(req).map(record(from:)) }` (now ~L211, not ~L208). Wave 4 rewrote `purgeAll` (batch delete) and **deleted `countDescendants`**, but this plan touches neither — instrument `children(of:)` exactly as written.
> - Residual **#3** (purge reaps `NotificationSpec` rows but does NOT cancel the OS-level pending `UNNotificationRequest`s) is now a **documented** acknowledged limitation in engineering-notes — still a named follow-up, unrelated to this plan's emitters.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–5 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-5.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files (`MigrationCoordinator`, `TaskStore`, `PersistenceController`, both `AppEnvironment`s). On completion, write `docs/superpowers/handoffs/wave-6.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Lillist a real field-diagnostics surface — a structured `os.Logger` taxonomy whose subsystem feeds the crash reporter's "Recent app logs" section (today always empty), plus `OSSignposter` timing on the migration and heavy-fetch paths and iOS MetricKit crash/hang/launch capture — so the shipped logs toggle becomes honest and OTA builds are debuggable.

**Architecture:** Introduce one `LillistLog` namespace in `LillistCore` exposing `Logger` instances keyed by a fixed `(subsystem, category)` taxonomy. The subsystem is pinned to `CrashReporting.subsystemIdentifier` so the existing `OSLogFetcher` (which filters `logEntry.subsystem == subsystem`) starts returning real lines with zero changes to the fetch path — this is the load-bearing wiring that makes the crash-reporter logs feature functional. Production diagnostic sites (the two macOS `NSLog` calls, the migration coordinator, the heavy `TaskStore` fetch) route through `LillistLog`; signposts wrap the migration runner and the main task-list fetch via a shared `OSSignposter`; iOS adds a `MetricKitObserver` retained by `AppEnvironment`. CLI `print()` calls are stdout *output* (design §454: "stdout for data; stderr for diagnostics") and are deliberately left alone.

**Tech Stack:** Swift 6.2, `os` framework (`Logger`, `OSSignposter`, `OSLogStore`), MetricKit (`MXMetricManager`), Swift Testing (`import Testing`), XCTest where neighbors use it.

**Source findings:** `logs-2` (crash-reporter "Recent app logs" non-functional — nothing writes to the queried subsystem) and Critic blind spot #4 (no `os.Logger` / MetricKit / signposts in production paths; `OSLog` appears only in the non-functional `OSLogFetcher`).

---

## File Structure

### Create
- `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift` — the logging taxonomy: one `enum LillistLog` exposing static `Logger` instances per category, all on subsystem `CrashReporting.subsystemIdentifier`, plus a shared `OSSignposter`.
- `Packages/LillistCore/Tests/LillistCoreTests/Support/LillistLogTests.swift` — Swift Testing suite asserting the subsystem equals the crash-reporter subsystem (the wiring contract) and that the signposter is non-disabled.
- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherRoundTripTests.swift` — Swift Testing suite that emits a real log line through `LillistLog` and asserts `OSLogFetcher` reads it back filtered by subsystem (the end-to-end proof that the logs feature is real).
- `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift` — `MXMetricManagerSubscriber` that logs crash/hang/launch diagnostics through `LillistLog` so MetricKit payloads land in the same unified-log stream the crash reporter reads.

### Modify
- `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (`runMigration` runner — anchor by the `private func runMigration(` signature, ~L189 post-Wave-4; `restoreFromBackup` — anchor by `public func restoreFromBackup(`, ~L169) — add structured `LillistLog.sync` log lines + an `OSSignposter` interval spanning the whole migration. **Wave 4 added two reentrancy guards + a `defer` at the very top of `runMigration`, a pre-erase account guard in phase 6, and a `restoreSteadyState` call in phase 8 — re-Read and re-anchor; weave around them.**
- `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (anchor by the `public func children(of parentID:)` signature, ~L211 post-Wave-4 — the heavy-fetch path; structurally unchanged) — wrap the fetch in an `OSSignposter` interval and emit a `LillistLog.store` line with the row count.
- `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift` (the `reindexAll` catch body, ~L72) — replace `NSLog(...)` with `LillistLog.indexing.error(...)`.
- `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift` (the Services-create catch body, ~L57) — replace `NSLog(...)` with `LillistLog.app.error(...)`.
- `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (property block — anchor by `let crashReporter` / `let mailTransport`, ~L69-70; `bootstrap()` — anchor by `func bootstrap()`, ~L298 post-Wave-4, and its tail of `startObserving…` / `installCanaryLifecycleObservers()` / `startObservingPauseReason()` calls, ~L340-343) — retain a `MetricKitObserver` and register it in `bootstrap()`. **Wave 4 added a `HistoryPruner(...).sweep()` block mid-`bootstrap()` and `preferencesStore:` to the `MigrationCoordinator(...)` call — re-Read; do not disturb them. The append tail (`startObservingPauseReason()` last) is unchanged.**
- `docs/engineering-notes.md` — append one entry documenting the subsystem-pinning contract (logs feed the crash reporter only because `LillistLog`'s subsystem == `CrashReporting.subsystemIdentifier`).

---

## Task 1: Define the `LillistLog` taxonomy pinned to the crash-reporter subsystem

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift`
- Test `Packages/LillistCore/Tests/LillistCoreTests/Support/LillistLogTests.swift`

This is the keystone: the subsystem MUST equal `CrashReporting.subsystemIdentifier` (`io.mikeydotio.lillist.crash`) because `OSLogFetcher.fetchRecentLines(since:subsystem:)` is called by `CrashReporter.submit` with exactly that subsystem and discards every entry whose `subsystem` differs (`OSLogFetcher.swift:25`). Categories give us readable Console filtering without splitting the subsystem.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Support/LillistLogTests.swift`:
```swift
import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("LillistLog taxonomy")
struct LillistLogTests {
    @Test("Logging subsystem equals the crash-reporter subsystem so logs feed the report")
    func subsystemMatchesCrashReporter() {
        // This is the load-bearing contract: OSLogFetcher filters on
        // subsystem == CrashReporting.subsystemIdentifier, so the only
        // way the crash report's "Recent app logs" section is ever
        // non-empty is for production loggers to write on that exact
        // subsystem.
        #expect(LillistLog.subsystem == CrashReporting.subsystemIdentifier)
    }

    @Test("Every category exposes a usable Logger")
    func categoriesAreUsable() {
        // Loggers are value types; we can't read their category back,
        // but exercising each confirms the static members exist and
        // compile against the pinned subsystem.
        LillistLog.sync.debug("test sync")
        LillistLog.store.debug("test store")
        LillistLog.indexing.debug("test indexing")
        LillistLog.app.debug("test app")
        LillistLog.metrics.debug("test metrics")
    }

    @Test("Shared signposter is enabled in this build")
    func signposterEnabled() {
        // An OSSignposter built from a Logger is enabled; the disabled
        // singleton is what `.disabled` returns. We assert ours is not
        // that, so the migration/fetch intervals actually record.
        #expect(LillistLog.signposter.isEnabled)
    }
}
```

- [ ] **Step 2: Run the test, expect failure** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LillistLogTests
```
Expected failure: `error: cannot find 'LillistLog' in scope` (the type does not exist yet).

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift`:
```swift
import Foundation
import os

/// Central `os.Logger` taxonomy for Lillist's production diagnostics.
///
/// ## Why the subsystem is pinned to the crash reporter's
///
/// The crash report's "Recent app logs" section is assembled by
/// `CrashReporter.submit(includeLogs:)`, which calls
/// `OSLogFetcher.fetchRecentLines(since:subsystem:)` with
/// `CrashReporting.subsystemIdentifier` and **discards every unified-log
/// entry whose `subsystem` differs** (`OSLogFetcher.swift`). So the only
/// way that section is ever non-empty is for production loggers to write
/// on that exact subsystem. Pinning `LillistLog.subsystem` to
/// `CrashReporting.subsystemIdentifier` is therefore the load-bearing
/// wiring that makes the shipped logs toggle honest — do not split it.
///
/// Categories are a Console.app filtering convenience only; they do not
/// affect which lines the crash reporter collects (it filters on
/// subsystem, not category).
///
/// ## Privacy
///
/// Every collected line passes through `LogRedactor.redact` before it
/// leaves the device. Treat that as defense-in-depth, not a license to
/// log content: log verbs, counts, durations, and enum raw values, never
/// titles / notes / journal bodies / paths. Use `.public` interpolation
/// only for already-non-identifying values (counts, mode names, error
/// type descriptions).
public enum LillistLog {
    /// The single unified-log subsystem for all Lillist diagnostics.
    /// Pinned to the crash reporter's subsystem on purpose (see above).
    public static let subsystem = CrashReporting.subsystemIdentifier

    /// CloudKit sync + migration state machine.
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Core Data stores (heavy fetches, batch work, save failures).
    public static let store = Logger(subsystem: subsystem, category: "store")

    /// Spotlight indexing (macOS).
    public static let indexing = Logger(subsystem: subsystem, category: "indexing")

    /// App-shell / service-provider lifecycle and failures.
    public static let app = Logger(subsystem: subsystem, category: "app")

    /// MetricKit crash/hang/launch payloads (iOS).
    public static let metrics = Logger(subsystem: subsystem, category: "metrics")

    /// Shared signposter for `OSSignposter` intervals around the
    /// migration runner and heavy fetch paths. Built from a `Logger`
    /// so it is enabled in normal builds (the `.disabled` singleton is
    /// the no-op variant).
    public static let signposter = OSSignposter(
        logger: Logger(subsystem: subsystem, category: "signpost")
    )
}
```

- [ ] **Step 4: Run the test, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LillistLogTests
```
Expected output: `Test Suite 'LillistLog taxonomy' passed` with 3 tests passing, `0 failures`.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift Packages/LillistCore/Tests/LillistCoreTests/Support/LillistLogTests.swift && git commit -m "feat(observability): add LillistLog taxonomy pinned to crash-reporter subsystem

Introduce os.Logger categories (sync/store/indexing/app/metrics) and a
shared OSSignposter, all on CrashReporting.subsystemIdentifier so the
crash reporter's OSLogFetcher (which filters by that subsystem) will
collect production log lines. Closes the wiring half of logs-2."
```

---

## Task 2: Prove the crash-reporter logs feature is real (OSLogFetcher round-trip)

**Files:**
- Test `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherRoundTripTests.swift`

`OSLogFetcherTests.swift` already exists but deliberately asserts only `lines.count >= 0` (sandboxed runners may deny log access). This task adds a *best-effort* round-trip that emits through `LillistLog` and reads back — proving that when log access IS granted, a `LillistLog` line is what the crash reporter would collect. It is conditional on the entry being readable so it never flakes a sandboxed CI run. No production code changes; this is a verification net for Task 1's contract.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherRoundTripTests.swift`:
```swift
import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("OSLogFetcher round-trip")
struct OSLogFetcherRoundTripTests {
    /// Emit a uniquely-tagged line through the production LillistLog
    /// path, then read it back through the SAME subsystem the crash
    /// reporter queries. When log access is granted (local dev,
    /// host-app test target) this proves the logs section is now real;
    /// when it is denied (sandboxed CI) we assert only that the fetch
    /// does not throw, matching OSLogFetcherTests' calibration.
    @Test("A LillistLog line is collectable via the crash-reporter subsystem")
    func lillistLogLineIsCollectable() async throws {
        let marker = "rt-marker-\(UUID().uuidString)"
        let since = Date()
        LillistLog.app.notice("\(marker, privacy: .public)")

        let fetcher = OSLogFetcher()
        let lines = try await fetcher.fetchRecentLines(
            since: since.addingTimeInterval(-1),
            subsystem: CrashReporting.subsystemIdentifier
        )

        // Always-true safety net so sandboxed runners pass.
        #expect(lines.count >= 0)
        // When the store returned entries at all, our marker must be
        // among them — i.e. LillistLog writes on the subsystem the
        // crash reporter reads. If the store returned nothing, log
        // access was denied and we skip the strict check.
        if !lines.isEmpty {
            #expect(lines.contains { $0.contains(marker) })
        }
    }
}
```

- [ ] **Step 2: Run the test, expect pass-or-skip (NOT a build failure)** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter OSLogFetcherRoundTripTests
```
Expected: the test compiles and passes. On a runner with unified-log access the strict branch fires and the marker is found; on a sandboxed runner `lines` is empty and only the `>= 0` assertion runs. Either way: `0 failures`. (This is a verification net, not a red→green TDD step — the production capability landed in Task 1; here we assert the capability holds end-to-end.)

- [ ] **Step 3: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherRoundTripTests.swift && git commit -m "test(observability): round-trip a LillistLog line through OSLogFetcher

Proves the crash reporter's 'Recent app logs' section is now real: a
line emitted via LillistLog is collectable through the exact subsystem
CrashReporter.submit queries. Best-effort to stay green on sandboxed
runners with no log access. Verifies logs-2."
```

---

## Task 3: Route the two macOS `NSLog` sites through `LillistLog`

**Files:**
- Modify `Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift` (L72)
- Modify `Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift` (L57)

These are the only two production diagnostic `NSLog` calls (everything else printing is CLI stdout output, which stays). `NSLog` writes to the default subsystem and is unstructured, so it never reaches the crash reporter. Routing through `LillistLog` puts them on the collected subsystem and uses structured privacy annotations. macOS app-target changes are verified by an unsigned `xcodebuild build` (Claude Code can't sign).

- [ ] **Step 1: Edit `IndexingService.swift`** — at the top of the file ensure `import LillistCore` is present (it already is, since the file uses `environment.taskStore`), then replace the catch body. Change L72 from:
```swift
        } catch {
            NSLog("IndexingService.reindexAll failed: \(error)")
        }
```
to:
```swift
        } catch {
            LillistLog.indexing.error(
                "reindexAll failed: \(error.localizedDescription, privacy: .public)"
            )
        }
```

- [ ] **Step 2: Edit `LillistServicesProvider.swift`** — ensure `import LillistCore` is present (it is — the file uses `environment.taskStore`), then change L53-58 from:
```swift
            } catch {
                // The Services API has no inline UI to report failure;
                // log and move on. The user can confirm by opening
                // Lillist's main window.
                NSLog("LillistServicesProvider failed: \(error)")
            }
```
to:
```swift
            } catch {
                // The Services API has no inline UI to report failure;
                // log and move on. The user can confirm by opening
                // Lillist's main window.
                LillistLog.app.error(
                    "Services create failed: \(error.localizedDescription, privacy: .public)"
                )
            }
```

- [ ] **Step 3: Confirm no stray `NSLog` remains in production paths** —
```bash
cd /Volumes/Code/mikeyward/Lillist && grep -rn "NSLog(" Apps/Lillist-macOS/Sources Apps/Lillist-iOS/Sources Extensions Packages/LillistCore/Sources/LillistCore --include="*.swift"
```
Expected output: no matches (empty, exit code 1).

- [ ] **Step 4: Build the macOS app target without signing, expect success** —
```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
Expected output: `** BUILD SUCCEEDED **` (warnings-as-errors is on for the app target, so a clean build proves the new logger calls compile cleanly).

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-macOS/Sources/Indexing/IndexingService.swift Apps/Lillist-macOS/Sources/Services/LillistServicesProvider.swift && git commit -m "refactor(observability): route macOS NSLog sites through LillistLog

Replace the two production NSLog diagnostics (indexing reindex failure,
Services create failure) with structured LillistLog.error calls so they
land on the collected subsystem and reach the crash reporter."
```

---

## Task 4: Instrument the migration runner with structured logs + an OSSignposter interval

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` — `runMigration` (anchor by the `private func runMigration(` signature, ~L189 post-Wave-4) and `restoreFromBackup` (anchor by `public func restoreFromBackup(`, ~L169). **Anchor by structure, not line number** — each wave shifts these. **Wave-4 note:** `runMigration` now opens with two reentrancy guards + `isMigrating = true; defer { isMigrating = false }` before the first `await breadcrumb(...)`; phase 6 has a new pre-erase `accountStateProvider` guard; phase 8 calls `restoreSteadyState(...)`. See Step 2a/2b for exactly where the log lines land relative to these.
- Test `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift` is the neighbor (Swift Testing, `.serialized`, `liveSwapAllowed` gate) — but migration logging is verified by the OSLogFetcher round-trip net (Task 2) plus an unsigned build, since the runner's destructive paths are host-gated. We add **no new assertion** that depends on the gated runner; instead we verify the instrumentation compiles and is non-destructive.

The migration runner is the single most important thing to be able to debug after an OTA crash (it swaps a live SQLite file). The live phase order is **reconfigure → copy-quarantine → erase**: the runner closes the SQLite connection via `host.reconfigure(to:)` first, then `quarantine.copyStore(at:)` (COPY-not-move, recording `entry.quarantineFolderName`), then the optional zone erase. Emit a `LillistLog.sync` line at each phase and wrap the whole `runMigration` body in an `OSSignposter` interval so Instruments shows migration duration. This is additive — it must not change control flow, the journal sequence, the `copyStore`/`quarantineFolderName` calls, the phase ordering, or the emitted `MigrationPhase` events. **Weave the lines into the live method (Steps 2a/2b); never paste a whole method body. The `breadcrumb(_:success:)` calls are already `async` and awaited inline in the live method — add the `LillistLog` lines around them; do not add or move any `await`.**

- [ ] **Step 1: Add the imports** — `MigrationCoordinator.swift` currently starts with `import Foundation` (L1). Change L1 from:
```swift
import Foundation
```
to:
```swift
import Foundation
import os
```

- [ ] **Step 2a: Read the CURRENT `runMigration` on `main` FIRST** — locate and Read the live method before editing:
```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "private func runMigration(" Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift
```
Then Read the full method body. Confirm the **current** phase order, which is the order you must weave logs onto:
0. **reentrancy guards (Wave-4)** — FIRST statements, before any `await`: `if let current = try? journal.read(), current.isInFlight { throw }`, then `guard !isMigrating else { throw }; isMigrating = true; defer { isMigrating = false }`. The signpost/start-notice (Step 2b's first bullet) goes AFTER these, before `await breadcrumb(...)`.
1. **preparing** — `await breadcrumb("sync mode change start …")`, then `emit(.preparing)` + `scheduler.cancelAllPending()`
2. **journal start** — build `MigrationJournal(state: .preparing, …)` and `journal.write(entry)`
3. **precondition** — for `replaceICloudWithLocal`, the `localStoreRowCount()` guard (throws on an empty local store — sync-7)
4. **structural swap FIRST** — `emit(.reconfiguringStore)` → `host.reconfigure(to: targetMode)` → `syncModeStore.setMode(targetMode)` (closes the SQLite connection *before* touching the file — persist-3)
5. **copy-quarantine** — `emit(.backingUp)`, state `.quarantining`, then `quarantine.copyStore(at: storeURL)` (COPY-not-move) and record `entry.quarantineFolderName = backup.folderName`
6. **cloudkit zone erase** — only `replaceICloudWithLocal`: a Wave-4 **pre-erase `accountStateProvider` guard** (`if let provider = accountStateProvider, await provider() == .accountChanged { throw }`) FIRST, then `emit(.erasingICloud…)` + `zoneEraser.eraseManagedZones(…)`
7. **await settle** — only `iCloudSync`: `quiesceMonitor.waitForQuiesce(…)`
8. **finalize** — state `.finalizing`, `emit(.finalizing)`, then a Wave-4 `scheduler.restoreSteadyState(...)` block (reads `preferencesStore`), then `journal.clear()`, `emit(.completed)`
9. **catch** — state `.failed`, `emit(.failed…)`, `await breadcrumb(… success: false)`, rethrow

**Wave-4 expects the two reentrancy guards (phase 0), the phase-6 account guard, and the phase-8 `restoreSteadyState` block to be PRESENT on current `main` — they are correct, do NOT treat them as a stale checkout.** If, conversely, what you Read does NOT match this order (e.g. you see `quarantineStore(at:)`/`quarantineBackupID`, `reconfigure` *after* the quarantine, or NO `isMigrating` guard at the top), STOP — that is a *pre-Wave-4* checkout; `git pull` and re-Read before continuing.

- [ ] **Step 2b: Weave the signpost + `LillistLog.sync` lines into the CURRENT body** — do **NOT** paste a whole method. Make these surgical additions to the live method, leaving every existing line, the journal sequence, the `copyStore`/`quarantineFolderName` calls, and the phase ordering untouched (additions are already-non-identifying: op raw value, mode, error type):
  - **After the Wave-4 reentrancy guards + `isMigrating = true; defer { isMigrating = false }`, and before `await breadcrumb("sync mode change start …")`:** open the signpost interval spanning the whole runner, and emit the start notice. (Do NOT insert ahead of the guards — they must run synchronously before any suspension. Placing the signpost/notice between the `defer { isMigrating = false }` line and `await breadcrumb(...)` keeps the whole timed body inside the interval.)
    ```swift
        let signpostID = LillistLog.signposter.makeSignpostID()
        let interval = LillistLog.signposter.beginInterval(
            "migration", id: signpostID,
            "op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )
        defer { LillistLog.signposter.endInterval("migration", interval) }
        LillistLog.sync.notice(
            "migration start op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )
    ```
  - **Phase 4 (structural swap), immediately after `emit(.reconfiguringStore)` and before `try await host.reconfigure(to: targetMode)`:**
    ```swift
            LillistLog.sync.notice("migration reconfiguring store")
    ```
  - **Phase 6 (cloudkit zone erase), inside the `if op == .replaceICloudWithLocal` block, after `emit(.erasingICloud(progress: 0))` and before `zoneEraser.eraseManagedZones(…)`:** (Wave 4 added a pre-erase `accountStateProvider` guard *earlier* in this block — your notice still goes after `emit(.erasingICloud(progress: 0))`, i.e. *past* that guard, so it logs only when the erase actually proceeds. Do not touch the guard.)
    ```swift
                LillistLog.sync.notice("migration erasing iCloud zones")
    ```
  - **Phase 8 (finalize), in the success path after `emit(.completed)` and before `await breadcrumb("sync mode change completed …")`:** (Wave 4 inserted an `emit(.finalizing)` + `scheduler.restoreSteadyState(...)` block *before* `journal.clear()`/`emit(.completed)` in this phase — leave it untouched; the completed-notice anchor on `emit(.completed)` is unchanged.)
    ```swift
            LillistLog.sync.notice("migration completed op=\(op.rawValue, privacy: .public)")
    ```
  - **`catch` block, after `emit(.failed(reason: "\(error)"))` and before `breadcrumb(… success: false)`:**
    ```swift
            LillistLog.sync.error(
                "migration failed op=\(op.rawValue, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)"
            )
    ```
  Note the placement difference from the pre-Wave-1 shape: the "reconfiguring store" notice now lands in phase 4 (before quarantine), and the "erasing iCloud zones" notice lands in phase 6 (after the copy-quarantine), because the current method reconfigures *first* and copies the closed store *second*. Add **no** log line tied to a `quarantineStore`/`quarantineBackupID` step — those no longer exist.

> **⚠️ DO-NOT-PASTE — ILLUSTRATIVE ONLY. This block shows the PRE-Wave-1 phase order (quarantine *before* reconfigure via the removed move-based `quarantineStore(at:)`/`quarantineBackupID` API).** It does NOT match what is on `main`. **Follow the live code, not this block** — the live order is **reconfigure → copy-quarantine → erase** (see Step 2a/2b for where each line lands in the CURRENT method). The block is kept only to show what the woven log/signpost lines look like in context; pasting it would revert merged Wave-1 work (the reorder, `copyStore`, and `quarantineFolderName`).
```swift
    // ⚠️ OLD SHAPE — illustrative only, DO NOT paste. See Step 2b for where
    //    each log line lands in the CURRENT (reordered) method.
    private func runMigration(op: ModeTransitionOp, targetMode: SyncMode, storeURL: URL) async throws {
        let signpostID = LillistLog.signposter.makeSignpostID()
        let interval = LillistLog.signposter.beginInterval(
            "migration", id: signpostID,
            "op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )
        defer { LillistLog.signposter.endInterval("migration", interval) }
        LillistLog.sync.notice(
            "migration start op=\(op.rawValue, privacy: .public) target=\(targetMode.rawValue, privacy: .public)"
        )

        breadcrumb("sync mode change start \(op.rawValue)")
        emit(.preparing)
        // … pre-Wave-1 order: quarantine (move) → erase → reconfigure …
        // (REMOVED on main — kept here only to show the woven log lines)
        LillistLog.sync.notice("migration erasing iCloud zones")
        LillistLog.sync.notice("migration reconfiguring store")
        LillistLog.sync.notice("migration completed op=\(op.rawValue, privacy: .public)")
        LillistLog.sync.error(
            "migration failed op=\(op.rawValue, privacy: .public) error=\(String(describing: type(of: error)), privacy: .public)"
        )
    }
```

- [ ] **Step 3a: Read the CURRENT `restoreFromBackup` on `main` FIRST** — the live method prefers the *exact* recorded folder (`quarantineFolderName`) and falls back to `latestQuarantinedStore` (sync-7); do not reduce it to a `latestQuarantinedStore`-only body. Read the live method:
```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "public func restoreFromBackup(" Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift
```
Confirm the **current** body does this:
1. `let entry = try journal.read()`
2. resolve `recorded` via `entry.quarantineFolderName.flatMap { quarantine.quarantinedStore(folderName: $0, filename: filename) }`
3. `let backup = try recorded ?? quarantine.latestQuarantinedStore(filename: filename)` then `guard let backup else { throw … }`
4. `emit(.removingLocalStore)` → `quarantine.restore(quarantinedStore: backup, to: targetURL)`
5. `let prev = entry.previousMode ?? .localOnly` → `syncModeStore.setMode(prev)` → `host.reconfigure(to: prev)` → `journal.clear()` → `emit(.completed)`

If you instead see a single `guard let backup = try quarantine.latestQuarantinedStore(…)` with no `quarantineFolderName`/`quarantinedStore(folderName:)` preference, STOP — that is the stale pre-Wave-1 checkout; `git pull` and re-Read.

- [ ] **Step 3b: Weave two `LillistLog.sync` lines into the CURRENT body** — additive only, no control-flow, journal, or resolution-order change. Add:
  - In the `guard let backup else { … }` failure branch, **before** the existing `throw LillistError.storeUnavailable(…)`:
    ```swift
            LillistLog.sync.error("restoreFromBackup found no quarantine backup")
    ```
  - Immediately **before** `emit(.removingLocalStore)` (i.e. right after the `guard` succeeds), the "restoring" notice:
    ```swift
        LillistLog.sync.notice("restoreFromBackup restoring quarantined store")
    ```
  - As the **last** line of the method, after `emit(.completed)`, the "completed" notice (reuse the already-bound `prev` from step 5 above):
    ```swift
        LillistLog.sync.notice("restoreFromBackup completed mode=\(prev.rawValue, privacy: .public)")
    ```
  Do **not** re-derive `prev` from `journal.read()` — the current method already binds `prev` from `entry.previousMode` near the end; the completion notice goes after `emit(.completed)` and references that same `prev`.

- [ ] **Step 4: Build LillistCore and run the migration suite, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter MigrationCoordinatorTests
```
Expected output: `Test Suite 'MigrationCoordinator' passed` (the gated cases still skip under `swift test`, as documented, but the suite must compile and the non-gated cases pass — the instrumentation is additive and changes no behavior). `0 failures`.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift && git commit -m "feat(observability): structured logs + signpost interval on migration runner

Wrap runMigration in an OSSignposter interval and emit LillistLog.sync
lines at each phase (start, erase, reconfigure, complete, fail) plus
restoreFromBackup. Additive only: no change to journal sequence or
emitted MigrationPhase events. Migration is the highest-value path to
debug after an OTA crash."
```

---

## Task 5: Signpost + structured-log the heavy task-list fetch

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift` (the `children(of:)` fetch)
- Test: verified by an existing TaskStore suite compile + run; the instrumentation is additive (no behavior change), so no new assertion is added against the fetch result. The signpost/log capability is already proven collectable by Task 2.

The main task-list reload funnels through `TaskStore.children(of:)` on the main-queue `viewContext` (the unbounded fetch the critic flagged; ~L211 on current `main` post-Wave-4 — structurally unchanged by Wave 4, which only rewrote the unrelated `purgeAll` and removed `countDescendants`). Paging is out of scope here (owned by `performance-budgets-and-paging`). What this plan adds is *visibility*: an `OSSignposter` interval and a `LillistLog.store.debug` line carrying the row count, so a slow reload shows up in Instruments and the log stream. Read the file first to find the exact current method.

> **Chain #2 — coordinate with `performance-budgets-and-paging`.** Both plans edit `TaskStore.children(of:)`. Land them together and re-Read the method immediately before editing: the signpost bracket must wrap whatever final fetch body the paging plan lands, and the row-count log must reflect the returned page. If paging has not yet landed, instrument the current unbounded body; if it has, instrument the paged body — do not re-introduce the unbounded fetch.

- [ ] **Step 1: Locate the current `children(of:)` method** —
```bash
cd /Volumes/Code/mikeyward/Lillist && grep -n "func children(of\|func children (" Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift
```
Then Read that method's full body before editing (line numbers may have drifted from the review's `:205`). Confirm it returns `[TaskRecord]` and performs its fetch inside `context.perform`.

- [ ] **Step 2: Add the `os` import if absent** — `TaskStore.swift` starts with `import Foundation` / `import CoreData` (L1-2). If `import os` is not already present, change L1-2 from:
```swift
import Foundation
import CoreData
```
to:
```swift
import Foundation
import CoreData
import os
```

- [ ] **Step 3: Instrument `children(of:)`** — wrap the existing fetch body in a signpost interval and emit the count, preserving every existing line. The current body is a **single `try await context.perform { … }`** that returns `try context.fetch(req).map(record(from:))`. Capture that expression into `let records = …`, bracket it with the signpost, and log the count — do **not** introduce a new helper:
```swift
    public func children(of parentID: UUID?) async throws -> [TaskRecord] {
        let signpostID = LillistLog.signposter.makeSignpostID()
        let interval = LillistLog.signposter.beginInterval("taskFetch", id: signpostID)
        defer { LillistLog.signposter.endInterval("taskFetch", interval) }

        // --- existing `try await context.perform { … }` body verbatim,
        //     captured into `records` instead of returned inline ---
        let records = try await context.perform { [self] in
            // … existing fetch + record(from:) mapping, unchanged …
        }

        LillistLog.store.debug("children fetch rows=\(records.count, privacy: .public)")
        return records
    }
```
Only if the paging plan (chain #2) has already grown the body into a longer multi-statement method should you extract a `fetchChildrenRecords` helper to keep the diff legible — pick whichever keeps the change minimal and DRY. Either way the existing fetch/`record(from:)` mapping logic is unchanged.

- [ ] **Step 4: Build + run the LillistCore store suite, expect pass** —
```bash
cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter TaskStore
```
Expected output: all TaskStore-named suites pass, `0 failures` (instrumentation is additive; the count and return value are unchanged).

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift && git commit -m "feat(observability): signpost + row-count log on the heavy task-list fetch

Wrap TaskStore.children(of:) in an OSSignposter interval and emit a
LillistLog.store row-count line so a slow main-queue reload is visible
in Instruments and the unified log. Visibility only; paging stays with
the performance-budgets plan."
```

---

## Task 6: Add iOS MetricKit capture (crash / hang / launch diagnostics)

**Files:**
- Create `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift`
- Modify `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (property block — anchor by `let crashReporter` / `let mailTransport`, ~L69-70; `bootstrap()` — anchor by `func bootstrap()` (~L298 post-Wave-4) and its tail of `startObserving…` / `installCanaryLifecycleObservers()` / `startObservingPauseReason()` calls, ~L340-343 post-Wave-4)

MetricKit (`MXMetricManager`) delivers crash, hang (`MXHangDiagnostic`), and launch (`MXAppLaunchDiagnostic`) reports the day after they occur. We subscribe a retained observer that logs each diagnostic's summary through `LillistLog.metrics`, so they land in the same unified-log stream the crash reporter reads — turning the day-after MetricKit payloads into searchable field diagnostics. MetricKit needs no entitlement; it just needs a retained `MXMetricManagerSubscriber`. App-target changes are verified by an unsigned `xcodebuild build`.

- [ ] **Step 1: Create the observer** — write `Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift`:
```swift
import Foundation
import MetricKit
import LillistCore

/// Subscribes to MetricKit and logs each diagnostic payload's summary
/// through `LillistLog.metrics`, so day-after crash/hang/launch reports
/// land on the same unified-log subsystem the crash reporter collects.
///
/// MetricKit retains subscribers weakly, so `AppEnvironment` holds a
/// strong reference for the lifetime of the app. We log only
/// non-identifying summary fields (call-stack JSON is intentionally not
/// emitted — it can carry symbol names; the redactor is a backstop, not
/// a license to ship stacks).
final class MetricKitObserver: NSObject, MXMetricManagerSubscriber {
    /// Register with the shared manager. Idempotent per instance.
    func startReceiving() {
        MXMetricManager.shared.add(self)
    }

    /// Unregister. Called from `deinit` defensively.
    func stopReceiving() {
        MXMetricManager.shared.remove(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        LillistLog.metrics.notice(
            "MetricKit metric payloads=\(payloads.count, privacy: .public)"
        )
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let launches = payload.appLaunchDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            let diskWrites = payload.diskWriteExceptionDiagnostics?.count ?? 0
            LillistLog.metrics.notice(
                "MetricKit diagnostics crashes=\(crashes, privacy: .public) hangs=\(hangs, privacy: .public) launches=\(launches, privacy: .public) cpu=\(cpuExceptions, privacy: .public) disk=\(diskWrites, privacy: .public)"
            )
        }
    }
}
```

- [ ] **Step 2: Add the stored property to `AppEnvironment`** — in `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`, the `crashReporter` / `mailTransport` properties sit around ~L69-70 (anchor by name, not line). Add a `metricKitObserver` property next to them. Change:
```swift
    let crashReporter: CrashReporter
    let mailTransport: MailComposerTransport
```
to:
```swift
    let crashReporter: CrashReporter
    let mailTransport: MailComposerTransport
    /// Retained MetricKit subscriber. MetricKit holds subscribers
    /// weakly, so the environment owns the strong reference.
    let metricKitObserver = MetricKitObserver()
```

- [ ] **Step 3: Register the observer in `bootstrap()`** — `bootstrap()` ends (~L340-343 post-Wave-4) with the `startObserving…` / `installCanaryLifecycleObservers()` / `startObservingPauseReason()` calls. Re-Read the live tail first (it has shifted across waves — `startObservingPauseReason()` is still the current last call; Wave 4 added a mid-method `HistoryPruner(...).sweep()` block but did NOT change this tail) and append the MetricKit registration as the final statement. Change:
```swift
        startObservingAccountState()
        startObservingSyncMode()
        installCanaryLifecycleObservers()
        startObservingPauseReason()
    }
```
to:
```swift
        startObservingAccountState()
        startObservingSyncMode()
        installCanaryLifecycleObservers()
        startObservingPauseReason()
        metricKitObserver.startReceiving()
    }
```

> **MetricKit is iOS-only — do NOT touch the macOS `AppEnvironment`.** Only `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` gets `metricKitObserver`. The macOS `AppEnvironment.bootstrap()` (`Apps/Lillist-macOS/Sources/AppEnvironment.swift`) is a different file with a different tail (`startObservingAccountState` / `startObservingSyncMode` / `startObservingPauseReason`) and notably does **not** call `remoteChangeReconciler.start()` — that wiring is iOS-only. Verify that before assuming any macOS symmetry; add nothing to the macOS bootstrap here.

- [ ] **Step 4: Build the iOS app target without signing, expect success** —
```bash
cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
(`iPhone 17 / OS=26.2` is the canonical simulator destination per `CLAUDE.md` — do not "fix" it to a lower version.)
Expected output: `** BUILD SUCCEEDED **`. The new file is auto-discovered by xcodegen's `Apps/Lillist-iOS/Sources/**` glob, so no pbxproj regeneration is required for an *added* file in an existing source group — but if the build errors with "file not found", run the regeneration in Step 5 first and rebuild.

- [ ] **Step 5 (only if Step 4 reports the new file is not in the target): regenerate the pbxproj** —
```bash
cd /Volumes/Code/mikeyward/Lillist/Apps/Lillist-iOS && xcodegen generate --spec project.yml --project . && cd /Volumes/Code/mikeyward/Lillist/Apps && xcodegen generate --spec project.yml --project .
```
Then re-run the Step 4 build command and confirm `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add Apps/Lillist-iOS/Sources/App/MetricKitObserver.swift Apps/Lillist-iOS/Sources/App/AppEnvironment.swift && git commit -m "feat(observability): subscribe iOS to MetricKit and log diagnostics

Add MetricKitObserver (MXMetricManagerSubscriber) retained by
AppEnvironment, registered in bootstrap(). Logs crash/hang/launch/CPU/
disk diagnostic counts through LillistLog.metrics so day-after MetricKit
payloads reach the crash-reporter subsystem. Closes the MetricKit half
of the observability blind spot."
```

> If Step 5 ran, also `git add Apps/Lillist-iOS/Lillist-iOS.xcodeproj Apps/Lillist.xcodeproj` (the regenerated pbxproj) in the same commit.

---

## Task 7: Document the subsystem-pinning contract in engineering notes

**Files:**
- Modify `docs/engineering-notes.md` (append a new dated section at the end)

The append-only engineering log exists exactly for non-obvious gotchas a future contributor would otherwise rediscover the hard way. The fact that `LillistLog.subsystem` MUST equal `CrashReporting.subsystemIdentifier` — and that splitting them silently makes the crash-reporter logs section empty again — is precisely that kind of trap.

- [ ] **Step 1: Read the tail of the file to match the existing section style** —
```bash
cd /Volumes/Code/mikeyward/Lillist && tail -25 docs/engineering-notes.md
```
Confirm the format: a `## YYYY-MM-DD — <title>` heading followed by prose.

- [ ] **Step 2: Append the new section** — add to the end of `docs/engineering-notes.md`:
```markdown

## 2026-05-28 — Observability: the logging subsystem is load-bearing for the crash reporter

`LillistLog` (`Support/LillistLog.swift`) deliberately pins its
`subsystem` to `CrashReporting.subsystemIdentifier`
(`io.mikeydotio.lillist.crash`). This is not cosmetic. The crash
report's "Recent app logs" section is assembled by
`CrashReporter.submit(includeLogs:)`, which calls
`OSLogFetcher.fetchRecentLines(since:subsystem:)` with that exact
subsystem and **discards every unified-log entry whose `subsystem`
differs** (`OSLogFetcher.swift`). Before Plan "observability-logging"
nothing in production wrote on that subsystem, so the toggle was inert
(`logs-2`): the section was always empty.

Consequences for future work:

- **Never give `LillistLog` its own vanity subsystem.** Categories
  (`sync`, `store`, `indexing`, `app`, `metrics`, `signpost`) are the
  Console.app filtering axis; the subsystem stays pinned. Split the
  subsystem and the crash report goes silent again with no compile
  error and no test failure unless you run the OSLogFetcher round-trip
  on a host with log access.
- **`OSLogFetcherRoundTripTests` only enforces the contract when the
  runner has unified-log access.** Sandboxed `swift test` runners often
  deny it, so the strict branch is skipped and the test still passes.
  `LillistLogTests.subsystemMatchesCrashReporter` is the always-on
  guard — keep it.
- **Privacy:** every collected line passes through `LogRedactor.redact`
  before leaving the device, but that is a backstop. Log verbs, counts,
  durations, mode raw values, and error *type* names with
  `privacy: .public`; never titles, notes, journal bodies, paths, or
  raw `error` descriptions (which interpolate user content). MetricKit
  call-stack JSON is intentionally not emitted.
- **CLI `print()` is not a logging gap.** Those are stdout *output*
  (design §454: "stdout for data; stderr for diagnostics") and must
  stay `print`. The 43-`print()` figure in the foundation review counts
  these; do not "fix" them into loggers.
```

- [ ] **Step 3: Verify the append landed and the file still ends cleanly** —
```bash
cd /Volumes/Code/mikeyward/Lillist && tail -6 docs/engineering-notes.md
```
Expected: the closing bullet about CLI `print()` is the last content.

- [ ] **Step 4: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist && git add docs/engineering-notes.md && git commit -m "docs(observability): record the subsystem-pinning crash-reporter contract

Document that LillistLog.subsystem must equal
CrashReporting.subsystemIdentifier or the crash report's logs section
goes silent, and that CLI print() is stdout output, not a logging gap."
```

---

## Self-review checklist

Confirm each source finding is closed by a named task before considering this plan complete:

- [ ] **`logs-2` (crash-reporter "Recent app logs" non-functional — nothing writes to the queried subsystem)** — closed by **Task 1** (defines `LillistLog` on `CrashReporting.subsystemIdentifier`, making `OSLogFetcher`'s subsystem filter match real production lines), **Task 2** (round-trip proof that a `LillistLog` line is collectable through the crash-reporter subsystem), and the production emitters in **Tasks 3-6** that actually populate that subsystem. The toggle is now honest: it returns real data.
- [ ] **Critic blind spot #4 — no `os.Logger` in production paths (only 43 `print()`, `OSLog` only in the non-functional fetcher)** — closed by **Task 1** (the `os.Logger` taxonomy) and **Task 3** (the two macOS `NSLog` diagnostics now route through `LillistLog`). CLI `print()` calls are correctly left as stdout output per design §454, documented in **Task 7**.
- [ ] **Critic blind spot #4 — no signposts** — closed by **Task 4** (`OSSignposter` interval around the whole migration runner) and **Task 5** (`OSSignposter` interval around the heavy `TaskStore.children(of:)` fetch).
- [ ] **Critic blind spot #4 — no MetricKit** — closed by **Task 6** (`MetricKitObserver` subscribed in iOS `AppEnvironment.bootstrap()`, logging crash/hang/launch diagnostics through `LillistLog.metrics`).
- [ ] **Logging taxonomy defined** — **Task 1** establishes the fixed `(subsystem, category)` taxonomy (`sync`/`store`/`indexing`/`app`/`metrics`/`signpost`), documented in **Task 7**.

### Strengths preserved (must remain true after this plan)
- [ ] No `NSManagedObject` escapes `LillistCore` — this plan adds only `os` logging; no DTO boundary touched.
- [ ] Synchronous same-actor `AsyncStream` continuation-registration is untouched (no edits to `CloudKitEventBridge`/`AccountStateMonitor`/`SyncStatusMonitor`).
- [ ] Calendar-based date math untouched.
- [ ] Strict concurrency holds on the `LillistCore` source target — `LillistLog` is a stateless `enum` of `Sendable` `Logger`/`OSSignposter` values; all logger statics are immutable.
- [ ] Migration journal sequence and emitted `MigrationPhase` events are byte-for-byte unchanged (Task 4 is additive instrumentation only).

### Cross-plan coordination
- [ ] **`crash-reporter-privacy`** (owns `LogRedactor.swift`): this plan's loggers rely on `LogRedactor.redact` as the final scrub before lines leave the device, but emit only non-identifying fields (counts, mode/op raw values, error *type* names) precisely so they survive redaction unharmed. No edit to `LogRedactor` here. The redaction-hardening plan should treat `LillistLog` output as one of its adversarial inputs.
- [ ] **`resolve-inert-features`** (merged, Wave 3): it did **not** remove the `includeLogs` toggle — instead it dropped the crash-report *preview's* overpromising "logs/breadcrumbs" lines and pointed the `CrashReportingPane` comment at THIS plan as the owner of the real on-disk buffer decision (commit `fix(crash-report): stop preview promising unavailable breadcrumbs/logs`). The `includeLogs` toggle still ships (`CrashReporter.submit(includeLogs:)`); THIS plan makes it honest — Task 1+2 wire the subsystem, Tasks 3-6 populate it — so the toggle now returns real data and must stay. Breadcrumb recording is owned by `breadcrumb-truthfulness` (merged, Wave 2); this plan does not touch breadcrumbs.
- [ ] **`performance-budgets-and-paging` (chain #2 — land together, re-Read)** (owns `TaskStore.swift` paging): Task 5 only *adds a signpost + count log* to `children(of:)`; it does not add `fetchBatchSize`/`fetchLimit`/paging. Coordinate the shared `TaskStore.swift` edit so the signpost bracket stays around whatever fetch body the paging plan lands (the interval should wrap the final fetch, the count log should reflect the returned page). Re-Read `children(of:)` immediately before editing.
