# Plan 3b — reset-propagation-safety

Findings: `S9c`, `S10`, `S18`, `S19`, `S20`, `S22`, `X11`. Stories: `LIL-32`, `LIL-33`,
`LIL-56`, `LIL-57`, `LIL-58`, `LIL-60`, `LIL-42`. Review doc:
`docs/reviews/2026-07-28-data-sync-review.md`. Ledger:
`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`.

Hotspots: `Sync/ResetSignalMonitor.swift`, `Sync/ControlInbox.swift`,
`Sync/ResetControlEvent.swift`, `Sync/ResetPropagator.swift`, `Sync/DeviceRoster.swift`,
`Sync/KeyValueSyncStore.swift`, `Sync/AppliedEventStore.swift`,
`Sync/DataStoreResetService.swift`, `Sync/MigrationCoordinator.swift`,
`Sync/CloudKitErrorClassifier.swift`, `Sync/CloudKitZoneEraser(Impl).swift`,
`Persistence/QuarantineManager.swift`, `Persistence/PersistentHistoryTokenStore.swift`,
`Persistence/HistoryPruner.swift`, `LillistCore/Widgets/WidgetSnapshotStore.swift`, both
apps' `AppEnvironment.swift`/`LillistApp.swift`, `LillistUI/Sync/*`,
`LillistUI/Settings/ICloudSyncSettingsSection.swift`.

## Binding product decision (recap)

Remote reset events are **never** auto-applied. The receiving device always prompts the
user before applying, regardless of the event's age. An expiry window remains as a pure
hygiene bound (never a safety mechanism, since apply is always confirmed either way).

## 1. S10 — always-prompt event flow

### State diagram

```
                 refreshPendingDecision() scan
                              |
         ,--------------------+--------------------,
         |                    |                     |
   already applied      undecodable payload    decodable, new/undecided
  (crash-recovery       (S22 dead letter)              |
   ack retry)                 |            ,------------+------------,
         |                    |            |                         |
      ack only          quarantine +   requestedAt          requestedAt within
                        ack + diag.    > 180 days               180 days
                              |            |                         |
                              |      ack + discard          currentSyncMode
                              |    (EXPIRED, diag.)          == .iCloudSync ?
                              |            |                    /        \
                              |            |                  no          yes
                              |            |                   |           |
                              |            |         ack + discard    PENDING-DECISION
                              |            |       (NOT-SYNCING,      (surfaced to UI,
                              |            |     user-visible note)   badge + dialog)
                              '------------+-------------------------------+
                                           |                                |
                                     (terminal: event                confirmApply()
                                      is gone from the                     |
                                      inbox either way)          apply() succeeds?
                                                                    /        \
                                                                  yes         no
                                                                   |           |
                                                        ack + mark-applied  stays
                                                        every currently-   PENDING
                                                        pending event      (error
                                                        (S10: one         surfaced
                                                        convergence       inline,
                                                        satisfies all)    retry on
                                                                          next
                                                                          confirm)

  PENDING-DECISION also reachable from "Not Now" (dismiss the dialog): no monitor
  call at all — `pendingDecision` stays set (still badge-visible/re-openable), the
  event stays un-acked in ControlInbox, and the NEXT refreshPendingDecision() scan
  (next KVS-changed notification or launch) re-evaluates it from scratch (expiry /
  mode / decodability all re-checked — nothing about "declined" is persisted).
```

Four terminal event-fates per scan pass: **applied** (user-confirmed, converges this
device), **expired** (180-day hygiene bound, silent ack+diagnostic), **not-syncing**
(local-only device — nothing to converge to — silent ack+diagnostic+user-visible note),
**dead-lettered** (undecodable payload — quarantined, not silently lost forever). The
*only* path to "applied" is `confirmApply()`, called exclusively from explicit UI
confirmation — there is no code path left that calls the underlying `apply` closure
(`DataStoreResetService.resetAndRedownload()`) without it.

### API shape

`ResetSignalMonitor` becomes an `actor` (this also closes `S22`'s `isApplying` race —
actor isolation serializes every access; no separate fix needed there beyond the type
change). New/changed shape:

- `init(inbox:applied:deviceID:breadcrumbs:currentSyncMode:deadLetters:clock:apply:)` —
  `currentSyncMode: @Sendable () async -> SyncMode` (default `{ .iCloudSync }`,
  permissive-default matching this program's `AccountStateProviding` precedent) is the
  new dependency the not-syncing branch needs; `deadLetters: ResetEventDeadLetterStore?`
  (new type, `S22`) is optional so every existing test construction still compiles;
  `clock: @Sendable () -> Date` (default `Date.init`) makes the 180-day boundary
  deterministically testable, matching `QuarantineManager`'s identical injection
  pattern.
- `pendingDecision: ResetControlEvent?` (async property) + `pendingDecisionStream:
  AsyncStream<ResetControlEvent?>` — the oldest currently-actionable, undecided event.
  Mirrors `AccountStateMonitor`'s `currentState`/`stateStream` dual-access shape.
- `discardNotice: ResetEventDiscardNotice?` + `discardNoticeStream` — the most recent
  auto-discarded event (expired or not-syncing), for the "user-visible note."
  `ResetEventDiscardNotice { event, reason: .expired | .notSyncing, discardedAt }`.
- `refreshPendingDecision()` **replaces** `checkAndApply()` — same call sites
  (bootstrap catch-up, KVS-changed notification), but never applies anything; only
  classifies and updates the two streams above.
- `confirmApply()` — the only way `apply` ever runs. No parameter: applies the anchor
  (oldest pending) event, and on success acks+marks-applied **every** currently pending
  event, not just the anchor — they all resolve to the identical "converge to current
  iCloud state" action (`ResetControlEvent.Kind`'s own doc comment already establishes
  this), so requiring N separate confirmations for N queued broadcasts would be
  needless friction. On failure, every pending event stays un-acked/un-applied exactly
  as `checkAndApply()`'s old failure path did — the next confirm (or scan) retries.
- "Decline" has **no dedicated method** — it is purely a UI-local dismiss (hide the
  sheet, leave `pendingDecision` set so the badge stays live and re-openable). This
  directly extends the `S3`-established precedent ("the non-blocking dialog must stay
  genuinely persistent... rather than silently disappearing across launches") rather
  than inventing new state — no council vote needed, this is the one defensible
  extension of an already-binding pattern.

### Expiry window — council decision

**180 days**, unanimous 3/3 in round 1 (no deliberation needed). Full audit trail:
`.council/reset-event-expiry-window/DECISION.md`. Rationale in brief: since apply is
always user-confirmed, the two failure directions are asymmetric — a too-short window
silently defeats the actual convergence mechanism issue #71 built (a bare CloudKit zone
delete does not "stick" on its own; `NSPersistentCloudKitContainer` just re-creates the
zone and re-uploads a peer's own data, resurrecting what a reset erased), while a
too-long window costs almost nothing (cheap KVS entries, rare/deliberate resets, still
requires an explicit tap). 90 days sits at the edge of the brief's own stated "weeks to
a few months" secondary-device dormancy window rather than comfortably past it; 180 days
clears it with real margin while remaining a genuine bound. Implementation: `Calendar`-
based day math (`Calendar.current.date(byAdding: .day, value: 180, to: event.requestedAt)`),
never `addingTimeInterval`/raw-seconds — this repo's own house rule
(`CLAUDE.md`/`RecurrenceExpander` precedent). Exactly-180-days-old counts as expired
(inclusive boundary).

### Local-only handling

`refreshPendingDecision()` checks `currentSyncMode()` **once per scan pass** (mode
doesn't change event-to-event within one scan). When `.localOnly`, every otherwise-
actionable event this pass is ack+discarded with `.notSyncing` — there is nothing to
converge to without a CloudKit connection, so surfacing "Apply Reset" would just throw
immediately anyway (the existing `resetAndRedownload()` guard). The discard notice
carries the sender's name so the UI copy can say "A reset request from Nephele's Mac
arrived while this device was in Local Only mode and could not be applied. Turn on
iCloud Sync to receive future requests." — a real, dismissible banner (see §5), not a
silent breadcrumb-only drop.

## 2. S22 — ControlInbox dead-letter quarantine + AppliedEventStore cap

- `ControlInbox` gains `undecodableKeys(for:) -> [String]` (every key under a
  recipient's prefix whose value fails to decode as `ResetControlEvent`) and
  `discardUndecodable(key:)` (removes by raw key — unlike `acknowledge(eventID:...)`,
  doesn't require having decoded an `id` first). `pendingEvents(for:)` itself is
  unchanged (still silently `compactMap`s past undecodable entries — a corrupt payload
  must never crash a scan) — the new methods are how a caller *notices* what that
  `compactMap` swallowed.
- New type `ResetEventDeadLetterStore` (`Sync/ResetEventDeadLetterStore.swift`) —
  `UserDefaults`-backed, mirrors `AppliedEventStore`'s exact shape (lock-protected,
  `.standard` suite default, capped at 50 entries oldest-evicted-first). Diagnostic
  only: nothing ever reads it back to retry: it exists so a corrupt-payload class of bug
  is discoverable (surfaced in a future Diagnostics export, out of this plan's scope —
  the type's job here is just "don't let it vanish with zero trace") rather than
  silently invisible forever, which is the actual finding.
- `AppliedEventStore` gains a 200-entry cap, oldest-evicted-first. Storage moves from
  `Set<String>` to an ordered `[String]` (`UserDefaults.stringArray`) since eviction
  needs an ordering `Set` doesn't have; `hasApplied`/`markApplied`'s O(n) cost against
  n≤200 is noise. Rationale (also the story's `Fix:` note): a personal account's reset
  events are rare, deliberate, user-initiated actions — 200 is generous headroom while
  guaranteeing the store can never grow unbounded across a device's lifetime; eviction
  only ever discards crash-recovery memory for a long-past event whose `ControlInbox`
  entry has almost certainly already been acknowledged and removed by every recipient
  (the store is explicitly *not* a correctness requirement — see its own header
  comment).
- `isApplying`'s race: closed by §1's actor conversion, not a separate change.

## 3. S20 — ResetPropagator.broadcast reports reach

New type `BroadcastOutcome` (`Sync/ResetPropagator.swift`):

```swift
public enum BroadcastOutcome: Sendable, Equatable {
    case notConfigured           // no ResetPropagator injected (test/legacy)
    case notified(peerCount: Int)
    case rosterEmpty             // no other device known yet — nobody was told
    case skippedQuiesceTimedOut  // S9c — re-export never settled; broadcast skipped
}
```

One type serves both `S20` (roster-empty visibility) and `S9c` (quiesce-timeout
visibility) since both are "the destructive op itself succeeded locally, but peers were
not told" — the same UI-facing shape ("your data is safe, but here's what didn't reach
other devices") applies to either cause.

`ResetPropagator.broadcast(_:now:) -> BroadcastOutcome` (was `Void`) returns
`.notified(peerCount:)` or `.rosterEmpty` based on `roster.knownPeers(excluding:)`'s
count — never silently treats an empty roster as success.

`DataStoreResetService.resetEverywhereToEmpty()` and `.resetAndReseedFromThisDevice()`
change their return type from `Void` to `BroadcastOutcome` (the two — and only two —
propagating reset flavors; `resetAllData()`/`resetAndRedownload()` never call
`propagator?.broadcast` and keep returning `Void`). Both apps' reset UI
(`ResetDataStoreSection.swift` iOS, `AdvancedPane.swift` macOS) branch the success
copy on the outcome instead of a single hardcoded "your other devices will erase and
reload" string — `.rosterEmpty` gets "No other devices are currently known on this
account, so nobody else was notified." instead.

## 4. S9c — reseed broadcast ordering

`resetAndReseedFromThisDevice()`'s current order is export → wipe → import → reconcile →
**broadcast** → journal-clear. The re-export triggered by the reimport's own Core Data
save has **no wait** before broadcasting — a peer that redownloads immediately can pull
a zone still mid-upload.

Fix: after the reimport (and its existing `backupReconciler?.reconcileFull()` call),
check `await host.currentMode == .iCloudSync`. If so, `await
quiesceMonitor.waitForQuiesce(minQuietWindow:, hardTimeout:)` before broadcasting:
- `.settled` → broadcast normally, return `.notified`/`.rosterEmpty`/`.notConfigured`.
- `.timedOut` → do **not** broadcast (a peer would pull a knowably-partial zone) —
  return `.skippedQuiesceTimedOut` instead, log+breadcrumb, and the reset/reseed itself
  is still reported as having succeeded locally (this device's data is intact and
  correctly reimported; only the cross-device notification was skipped).

This is a **third, distinct** quiesce-timeout posture beyond `2a`'s established
asymmetric pair (pre-destructive fail-closed / post-destructive log-and-proceed): here
the destructive work already succeeded (nothing to revert) *and* the timeout changes
what happens next (skip a specific side-effect) rather than either blocking or silently
proceeding as if nothing happened. Direct call, no council needed — the "don't tell
peers to redownload a knowably-partial zone" conclusion follows straightforwardly from
the finding's own text once traced against `waitForQuiesce`'s documented contract; there
is no second defensible reading.

No new `ReseedJournal.Phase` case: per `2a`'s established precedent ("no recovery-
behavior difference hinges on which sub-step crashed"), a crash during this quiesce-wait
recovers identically to a crash right after import completes — `recoverInterruptedReseed()`'s
existing resume branch (re-run the idempotent import) is correct either way.

**Discovered, out-of-scope residual (flagged per the `LIL-77`/`LIL-81` precedent, not
fixed here):** `recoverInterruptedReseed()`'s resume branch never calls
`propagator?.broadcast(...)` at all, crashed-or-not — a crash-recovered reseed never
notifies peers even after the fix above. Narrow, pre-existing, and out of this plan's
seven named findings; worth a future wave.

## 5. X11 — history-token watermarks + widget cache after store destroy/rebuild

**Which ops actually destroy/rebuild the store** (re-verified against current
`MigrationCoordinator.swift`/`DataStoreResetService.swift`, not assumed from the
finding's prose): `DataStoreResetService.performReset` — **every** flavor
(`resetAllData`/`resetAndRedownload`/`resetEverywhereToEmpty`/the wipe half of
`resetAndReseedFromThisDevice`) — always calls `host.rebuildEmptyStore()`. In
`MigrationCoordinator`, only `.replaceLocalWithICloud` does (`host.rebuildEmptyStore()`
then `reconfigure`). The other three migration ops (`.replaceICloudWithLocal`,
`.syncFirstThenDisable`, `.disableNow`) call `tearDownStore`+`attachStore` against the
**same on-disk file** — no destroy, so their persistent-history tokens stay valid and
must **not** be cleared (that would force a needless full replay). This matches the
wave brief's own scoping ("reset flavors, replaceLocal") exactly.

**Enumerated watermark keys** (new type `HistoryWatermarks`,
`Persistence/HistoryWatermarks.swift` — a deliberately narrow, hand-maintained seam;
`5c` (`watermark-registry-pruning`) formalizes a real `WatermarkRegistry` consumers
register themselves into, per the ledger's chain-6 forward-reference note):

1. `PersistentHistoryTokenStore.defaultKey` — `RemoteChangeReconciler`.
2. `PersistentHistoryTokenStore.diagnosticsKey` — `DiagnosticHistoryObserver`.
3. `PersistentHistoryTokenStore.backupKey` — `LocalBackupCoordinator`.
4. `HistoryPruner.tokenDefaultsKey` — the pruner's own bookkeeping key. Verified (via
   direct source read) that `HistoryPruner.sweep()` never actually reads this key back
   to resume (it always reads the *current* token straight off the coordinator) — so
   this is stale-but-inert today, not a live replay/deaf-consumer bug like the other
   three. Cleared anyway for hygiene/correctness-by-construction, since a future change
   to `sweep()` that started reading it back would otherwise silently inherit this same
   defect.

`HistoryWatermarks.clearAll()` sets `lastToken = nil` on the three
`PersistentHistoryTokenStore`s and removes key 4 from the shared App-Group
`UserDefaults`. Both `AppEnvironment.swift`s construct one instance and inject it as a
new `historyWatermarksReset: (() async -> Void)?` closure into `DataStoreResetService`
(called unconditionally in `performReset`'s success path, alongside the existing
`backupReconciler?.reconcileFull()`/`syncStatusReset?()` calls) and into
`MigrationCoordinator` (called only when `op == .replaceLocalWithICloud`, in the
same conditional guard as the new widget-cache-reset call below, right before
`journal.clear()`).

**Widget cache.** `WidgetSnapshotStore` gains `clearAll()` (deletes the whole
`Widget/` directory tree — defense-in-depth against `WidgetSnapshotBuilder.regenerate()`'s
existing per-filter-failure-is-silently-skipped design, which could otherwise leave a
stale filter snapshot behind even after a "successful" regenerate).
`WidgetSnapshotBuilder` forwards via `clearCache()`. App-layer `WidgetRefreshCoordinator`
(WidgetKit-importing, can't live in `LillistCore`) gains `resetAfterDestructiveOp()
async` — `@MainActor`, no internal `Task` spawn (unlike `scheduleRefresh()`/`refreshNow()`'s
fire-and-forget shape) so it can be properly `await`ed for deterministic sequencing —
which clears, regenerates against the now-current (likely empty) store state, and
reloads every timeline. Both apps wire this as a new `widgetCacheReset: (() async ->
Void)?` closure, called at the identical points as `historyWatermarksReset` above, PLUS
a second call in `resetAndReseedFromThisDevice()` right after its extra
`backupReconciler?.reconcileFull()` call (mirroring `S23`'s "deterministic, not reliant
on the local-save observer's incidental timing" reasoning — the reimported data should
be reflected in widgets without waiting for the natural remote-change observer to
eventually fire) and in `recoverInterruptedReseed()`'s resume branch, same reasoning.

Neither new closure is declared `@Sendable` (unlike `syncStatusReset`) — both
`DataStoreResetService`/`MigrationCoordinator` are already `@MainActor`-isolated classes,
so a plain `(() async -> Void)?` stored property needs no Sendable capture gymnastics for
`widgetCacheReset` to capture the non-Sendable, `@MainActor`-isolated
`WidgetRefreshCoordinator` cleanly. `HistoryWatermarks` itself stays a plain `Sendable`
struct (its only members are the already-`@unchecked Sendable`
`PersistentHistoryTokenStore` and `UserDefaults`), so its own closure could have been
`@Sendable` either way — kept un-`@Sendable` for consistency with its sibling.

## 6. S19 — resumable zone-erase + CloudKitErrorClassifier + iCloud-not-empty guard

Three independent sub-fixes:

1. **`CloudKitErrorClassifier`**: add `.zoneNotFound`/`.userDeletedZone` to
   `recoverableCodes` (affects both the top-level `severity(of:)` switch and the
   `.partialFailure` per-item tally, since both consult the same set) so
   `SyncStatusMonitor` never latches a permanent red badge for a condition
   `NSPersistentCloudKitContainer` recreates and re-uploads through on its own. `classify(_:)`
   gains explicit cases for both codes returning a distinguishing `.syncFailure(underlying:)`
   message ("iCloud's zone was deleted or is missing; it will be recreated automatically
   on the next sync.") instead of falling through to the generic `default` case's
   uninformative text. No new `LillistError` case — reusing `.syncFailure` avoids
   rippling a new case through its one exhaustive switch (`LillistError.swift`'s
   `errorDescription`, confirmed the only exhaustive switch over this type) for a
   condition that's really just a distinctly-worded sync failure, not a distinct
   category of error the rest of the codebase needs to branch on.

2. **"Try Again" resumability**: traced to its actual current implementation
   (`Apps/*/Sources/App|Preferences/LillistApp.swift`'s `onTryAgain: { try?
   environment.migrationJournalStore.clear(); launch = nil }`) — it **only clears the
   journal and dismisses the sheet**, never re-invokes the failed operation. A partial
   zone-erase (or any other partial step) is left exactly as the failure's `catch`
   block left it (reattached, un-migrated) with no retry ever actually attempted; the
   user must notice sync is still off/on the wrong side and manually re-toggle in
   Settings. New `MigrationCoordinator.retryFailedOperation(from journal:
   MigrationJournal, storeURL: URL) async throws` — clears the journal (required:
   `runMigration`'s reentrancy guard treats any non-idle state, including `.failed`, as
   "already in progress" and would otherwise refuse to start the very retry this method
   exists to perform) then dispatches `journal.operation` back through
   `beginEnable`/`beginDisable` (`.replaceICloudWithLocal` → `beginEnable(.replaceICloud)`,
   `.replaceLocalWithICloud` → `beginEnable(.replaceLocal)`, `.syncFirstThenDisable` →
   `beginDisable(.syncFirst)`, `.disableNow` → `beginDisable(.now)`), so the operation
   actually re-runs from the top — a fresh `runMigration` naturally re-attempts every
   step, including a previously-partial erase (re-erasing an already-empty zone is a
   safe no-op query). Both apps' `onTryAgain` closures call this instead of the bare
   `journal.clear()`, with the exact same catch→re-check-journal→re-present-or-dismiss
   shape the file already uses for `.iCloudUnavailable`'s `beginDisable` call.

3. **iCloud-not-empty guard for `.replaceLocalWithICloud`**: symmetric to the existing
   `localStoreRowCount`/`LillistError.localDataEmpty` guard on `.replaceICloudWithLocal`
   (refuses to erase iCloud for an empty local store). New `LillistError.iCloudDataEmpty`
   case (mirrors `.localDataEmpty`'s exact shape — no payload, the remedy is always the
   same). New `CloudKitZoneEraser.hasAnyRecords(in:) async throws -> Bool` method
   (reuses `LiveCloudKitZoneEraser`'s existing `fetchAllCustomZones`/managed-zone-filter
   logic; a managed zone with zero enumerable record-zone-changes counts as empty — the
   "lightweight query" the story calls for, via `CKFetchRecordZoneChangesOperation`
   with a fresh token and a 1-record result limit, avoiding any dependency on Core
   Data's internal `CD_*` record-type names). `MigrationCoordinator` gains a
   `remoteZoneHasRecords: (@Sendable () async throws -> Bool)?` constructor parameter
   (`nil` → no pre-flight, matching every other optional guard's legacy-safe default),
   consulted right before `.replaceLocalWithICloud`'s `host.rebuildEmptyStore()` call
   (same relative position as the existing account-changed pre-flight) — a `false`
   result throws `.iCloudDataEmpty` before any destructive work runs. Hard guard, not a
   soft dismissible warning: matches the existing sibling guard's own shape exactly (no
   2-genuinely-defensible-alternatives bar met for treating this one differently).

## 7. S18 — QuarantineManager.cleanupExpired() wiring

`AppEnvironment`'s `quarantine: QuarantineManager` local (constructed in `private init`,
used only to build `migrationCoordinator`/`dataStoreReset`) is promoted to a stored
`let` property. `bootstrap()` calls `try? quarantine.cleanupExpired()` right after the
`TreeIntegrityChecker.repair` block and `preferencesStore.normalizeSingletons()` have
both already run ("after the integrity/singleton passes," per the wave brief) — a
best-effort maintenance step, matching every other opportunistic bootstrap cleanup
(`autoPurgeJob.run()`) in shape. App-level only; no host-side unit test target reaches
`AppEnvironment.bootstrap()` (same precedent as `2a`'s `S16`/`S17` and `3a`'s app-wiring
rows) — verified via unsigned `xcodebuild build` for both apps. The same-second
folder-collision half of this finding was already fixed in Wave 1c (`070ba738`, the
`label` parameter) — verified present at `QuarantineManager.folderName(label:)` in
current `HEAD`; not duplicated here.

## Commit plan

1. `docs(plans): plan-3b reset-propagation-safety` (this file).
2. `feat(core): ResetSignalMonitor becomes an always-prompt actor with expiry + local-only discard (S10, S22 isApplying)`.
3. `feat(core): ControlInbox dead-letter quarantine + AppliedEventStore capacity bound (S22)`.
4. `feat(core): ResetPropagator.broadcast reports reach via BroadcastOutcome (S20)`.
5. `feat(core): resetAndReseedFromThisDevice waits for re-export quiesce before broadcasting (S9c)`.
6. `feat(core): clear history-token watermarks + widget snapshot cache after a destructive store reset/rebuild (X11)`.
7. `feat(core): CloudKitErrorClassifier treats zoneNotFound/userDeletedZone as recoverable + iCloud-not-empty guard for replaceLocal (S19)`.
8. `fix(core): "Try Again" actually re-runs the failed migration op instead of only clearing the journal (S19)`.
9. `fix(apps): wire QuarantineManager.cleanupExpired() into the bootstrap maintenance window (S18)`.
10. `feat(apps): wire pending-reset-decision dialog, discard notices, broadcast-outcome copy, and real retry into both apps (S9c, S10, S19, S20)`.
11. `chore(stories): move plan-3b stories to done`.

Two-hats: commit 2 necessarily rewrites `ResetSignalMonitorTests.swift` in full (every
existing test asserts the auto-apply behavior the fix removes — there is no way to land
the always-prompt fix and keep the old assertions, the same carve-out `2a`'s closing
report already established for this exact situation), landed in the same commit as the
behavior change, not separately.

## Verification

Per the ledger's binding protocol: `swift test --package-path Packages/LillistCore
--parallel --num-workers 2`, unmasked exit code + grep for failure markers, twice in a
row, after the `LillistCore`-only commits and again after the final app-wiring commit.
Both apps built unsigned (`xcodebuild ... CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
CODE_SIGNING_ALLOWED=NO build`) after every app-touching commit. Two-device propagation
verification (the always-prompt dialog, the discard notice, the broadcast-outcome copy)
is Mikey-only — enumerated in the ledger's manual-verification checklist.
