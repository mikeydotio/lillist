# Lillist Data Layer & Sync Hardening Review — 2026-07-28

**Verdict: `structurally-sound-but-actively-hazardous`.** The stores/persistence,
CloudKit sync, and cross-process layers are well-decomposed — the same
disciplined patterns the 2026-05-28 Foundation Review praised are still
present. But this sweep found **70 independently-catalogued defects**,
concentrated in exactly the paths a task manager can least afford them: trash/
restore, migration/backup/reset, and cross-device convergence. Several are
silent, unrecoverable, user-facing data loss; two (`C4`/`X4`) are suspected
live in the **Production** CloudKit environment today.

## Context & method

Mikey asked for a defect-hunting review of the data layer and sync features —
races, edge cases, illegal/inconsistent states — plus a remediation plan
optimized for long-term health and maintainability. Three parallel review
sweeps were run, each grounded directly in source (no speculation):

1. **Stores/persistence sweep** — `TaskStore` and the other six stores,
   `CascadeReaper`, `TaskDuplicateReconciler`, fractional ordering, breadcrumb/
   rollback discipline.
2. **Sync machinery sweep** — `MigrationCoordinator`, `PersistenceHost`,
   backup/restore, account identity, reset propagation, quiesce/journal
   plumbing.
3. **Cross-process / time-based sweep** — the six processes that can open the
   store (iOS app, macOS app, iOS + macOS widgets, `lillist` CLI, Share/
   Shortcuts extensions), history-token watermarks, recurrence idempotency,
   notification scheduling across process boundaries.

Every **Critical**-severity claim below was independently re-verified against
source before inclusion (marked **✓**). `C4`/`X4` (batch-delete CloudKit
export) is the one claim that cannot be settled by code reading alone — it is
carried as unverified-but-actionable and is on Mikey's manual-verification
checklist, **not** a gate on the fix (the fix proceeds regardless, per the
documented Apple limitation with mirrored-context deletes).

This document is the **findings record**. The remediation plan — waves,
per-finding story assignments, shared-file serial chains, and resume protocol
— lives in the living ledger:
[`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`](../superpowers/plans/2026-07-28-data-sync-hardening-index.md).

## Executive summary

Five through-lines dominate the 70 findings:

1. **The trash/restore/cascade state machine has no single source of truth**
   for the interaction of `deletedAt` × `archivedAt` × "parent is trashed" ×
   parent-child cycles. `CascadeReaper` recurses `children` with no
   `deletedAt` filter (`C1`), `restore(id:)` only clears the child's own flag
   and stray-orphans it (`C2`), and the duplicate reconciler deletes a loser's
   entire subtree with no re-pointing (`C3`) — each individually reachable,
   and `C2` directly feeds `C1`'s victim pool. CloudKit's property-level merge
   can recreate these illegal states no matter how carefully local code
   guards them, which is why the remediation program adopts a
   `TreeIntegrityChecker` class-killer rather than another point fix.
2. **Migration, backup/restore, and reset machinery routinely lies about
   success.** "Permanently replace this device's data" doesn't wipe local
   data (`S1`); `restoreFromBackup` can crash into a stranded, unlinked store
   inode while claiming success (`S2`); a peer offline for months will
   silently apply a stale "Reset Everywhere" the moment it reconnects,
   destroying unrelated offline work (`S10`); and multiple state stores
   (`SyncModeStore`, history watermarks, the migration journal) advance
   *before or regardless of* the destructive work's actual success (`S8`,
   `H6`).
3. **Six processes independently reinvent "where is the store on disk,"** and
   at least three of those inventions disagree. The macOS app never joined
   the App Group (`X1`) — its widget silently opens a second, empty
   `Lillist.sqlite` and, in iCloud mode, imports the *entire account* into
   that throwaway file. The `lillist` CLI builds a third path and has
   apparently never successfully opened the real store (`X2`). No test opens
   two `PersistenceController`s against one file, so none of this was ever
   visible to CI.
4. **Export, import, and backup completely and silently drop `Series`,
   `NotificationSpec`, and `archivedAt`** (`X3`) — there are no DTOs for them
   anywhere in `ExportSchema`/`BackupSchema`. Every "reset and reseed from
   this device," every backup restore, and every manual export/import
   permanently destroys all recurrence series, all reminders, and all archive
   state, on every device that resyncs from that data.
5. **Batch-delete purge may not export to CloudKit at all** (`C4`/`X4`) —
   `NSBatchDeleteRequest` bypasses the object graph `NSPersistentCloudKitContainer`
   normally tracks, so an emptied Trash may silently resurrect from the zone
   on the next import. This is suspected to be live in Production data since
   the 2026-06-24 cutover; see Mikey's checklist.

## Top risks

| Sev | Risk | IDs |
|---|---|---|
| **CRITICAL** | Cascade purge permanently deletes live descendants of a trashed ancestor; restore can strand a child in an unreachable, orphaned state that feeds the purge. | `C1`, `C2` |
| **CRITICAL** | "Replace this device's data with iCloud" never wipes local data — it merges instead, contradicting the UI's promise. | `S1` |
| **CRITICAL** | Backup restore can crash mid-swap into a permanently stranded store while reporting success to the user. | `S2` |
| **CRITICAL** | No persisted iCloud account identity — switching Apple ID accounts on a device can upload one user's data into another user's CloudKit account. | `S3` |
| **CRITICAL** | The macOS app's store was never migrated into the App Group; its widget opens a second empty store and can import the whole account into it. | `X1` |
| **CRITICAL** | Export/import/backup silently and permanently destroy every recurrence series, reminder, and archive flag on round-trip. | `X3` |
| **CRITICAL** | A stale "Reset Everywhere" event applies unconditionally on reconnect, destroying months of a peer's offline work with no expiry or confirmation. | `S10` |
| **CRITICAL** | Batch-delete purge may bypass CloudKit's export path — purged tasks can resurrect from the zone. Suspected live in Production. | `C4`/`X4` |

---

## Findings inventory

70 unique findings (the sync sweep's `S9` splits into `S9a`/`S9b`/`S9c` for
remediation granularity — 3 distinct failure modes sharing one root cause;
`C4` and `X4` describe the same defect independently found by two sweeps and
are merged into one entry, tagged `C4`/`X4`).

### Critical (12)

#### Stores/persistence

- **`C1` ✓ — Trash purge hard-deletes live descendants of a trashed ancestor.**
  `AutoPurgeJob.run` + `TaskStore.batchPurge` fetch `deletedAt != nil` roots,
  then `CascadeReaper.objectIDs(forDeleting:)` recurses `children` with **no
  `deletedAt` filter** (`CascadeReaper.swift:74-79`).
  **Failure scenario:** reachable via `C2` (restore a child while its parent
  stays trashed, then the parent's purge sweep reaps the "restored" child
  too) or via a CloudKit import adding a new child under an already-trashed
  parent. Silent, unrecoverable data loss.

- **`C2` ✓ — Restore of a cascade-trashed child strands it invisibly.**
  `restore(id:)` clears `deletedAt` on the child only (`TaskStore.swift:737-754`);
  the parent stays trashed. The child is now in no list — not the parent's
  children (parent is trashed/hidden), not root children (it has a parent) —
  and becomes `C1`'s next victim.
  **Product decision (Mikey, 2026-07-28):** restoring a child whose parent is
  still trashed **promotes the child to root**, severing the link to the
  trashed parent. See *Product decisions* below.

- **`C3` — TaskDuplicateReconciler "merge" deletes the loser's whole subtree.**
  `ctx.delete(loser)` cascades children/journal entries/attachments with no
  re-pointing or field merge (`TaskDuplicateReconciler.swift:134-137`).
  **Failure scenario:** an issue-#66-shaped duplicate-ID collision (the class
  that motivated the original reconciler) can now lose an entire subtree of
  subtasks, notes, and attachments attached to whichever row loses the merge.

- **`C4`/`X4` (verify on device) — Batch deletes may not export to CloudKit.**
  `purgeAll`/`AutoPurgeJob` use `NSBatchDeleteRequest` directly against the
  live `NSPersistentCloudKitContainer` store. Batch operations bypass the
  managed-object graph; if `NSPersistentCloudKitContainer` does not export
  these deletions the way it exports context-level deletes, an emptied Trash
  can **re-import from the CloudKit zone** — the purged tasks resurrect.
  Corroborated independently by both the stores sweep (`C4`) and the
  cross-process sweep (`X4`): purged-task `CKRecord`s are never explicitly
  retired, resurrected rows have no local same-`id` row for
  `TaskDuplicateReconciler` to heal, and this has been possible in
  **production data since the 2026-06-24 Production cutover**. Needs
  empirical verification (Dev-signed build + CloudKit Console); the fix does
  **not** wait on that verification.

#### Sync machinery

- **`S1` ✓ — `replaceLocalWithICloud` never deletes local data.** `runMigration`
  (`MigrationCoordinator.swift:245-348`) has no op-specific wipe step — it
  just attaches mirroring. Local rows upload and **merge** with iCloud, even
  though the UI promises this action "permanently replaces this device's
  data." `MigrationPhase.removingLocalStore` exists as a case but is never
  emitted by any migration path — the designed step was never wired up.

- **`S2` ✓ — `restoreFromBackup` can crash into a permanently stranded store.**
  It moves the live store file out from under an *open* coordinator, and
  `reconfigure(to: prev)` no-ops when `prev == currentMode` — a crash landing
  at `.preparing` leaves the app writing to an unlinked inode
  (`MigrationCoordinator.swift:170-189`, `PersistenceHost.swift:124`).
  **Failure scenario:** restored data is invisible, the journal is cleared,
  and the user is told recovery succeeded.

- **`S3` — No persisted account identity permits cross-account data bleed.**
  Nothing records `ubiquityIdentityToken`/`userRecordID` anywhere;
  `iCloudAccountState.from` maps *any* signed-in account to `.available`, and
  `.accountChanged` is only ever produced by a test seam — never in
  production (no `accountStateProvider` is passed by either app, there is no
  `CKAccountChanged` observer, and `refresh()` runs once per launch).
  **Failure scenario:** a device signs out of iCloud account A and into
  account B without relaunching; the app has no way to detect the switch and
  can upload account A's data into account B's private database.

- **`S4` — `restore(from: .livePackage)` reads the package *after* the
  destructive wipe.** A remote-change tick landing during the reset's
  quiesce window makes `LocalBackupCoordinator.processRemoteChange` prune the
  now-"stale" package to empty (`BackupRestoreService.swift:100-127`,
  `LocalBackupCoordinator.swift:261-265`). **Failure scenario:** restore
  reports success with zero tasks, and the backup package that would have
  let the user retry is itself destroyed in the process.

#### Cross-process / time-based

- **`X1` ✓ — The macOS app's store is not in the App Group.** macOS uses
  `StoreConfiguration.defaultOnDisk` (`Apps/Lillist-macOS/Sources/AppEnvironment.swift:374`,
  the sandbox container) while iOS uses `appGroupOnDisk`. **Failure
  scenario:** the macOS widget resolves the App Group path, finds nothing,
  and opens/creates a **second, empty** `Lillist.sqlite`; it shows zero data,
  and in iCloudSync mode arms its own mirroring delegate, importing the
  *entire account* into that throwaway file. Violates the repo's own Plan 8
  rule that the App Group container is the only sanctioned path for app/
  extension store sharing.

- **`X2` ✓ — The `lillist` CLI opens a third, different path.** `StoreLocator`
  builds `<group>/Library/Application Support/Lillist/Lillist.sqlite`;
  `appGroupOnDisk` (used by iOS) builds `<group>/Lillist/Lillist.sqlite`; the
  macOS app uses neither (see `X1`). **Three path conventions across six
  processes, pinned together by no test.** The CLI therefore always throws
  "store not found," or — worse, if a stale file happens to exist at its
  path — silently operates on a divergent, out-of-sync copy.

- **`X3` ✓ — Export/import/backup silently drop `Series`, `NotificationSpec`,
  and `archivedAt`.** `ExportSchema.swift` has no DTOs for either entity;
  `Importer.applyTask` never sets `row.series`; `BackupSchema` reuses the
  same incomplete `TaskDTO`. **Failure scenario:**
  `resetAndReseedFromThisDevice` (export → wipe local + iCloud → import)
  permanently destroys every recurrence series, every reminder, and all
  archive state — **on every device**, since the reseed becomes the new
  source of truth the rest of the account converges to. The identical loss
  happens on every backup restore and every user-initiated export/import.

- **`X5` — Widget cache-miss rebuild treats an empty filter list as success.**
  `pruneFilters(keeping:)` then deletes every snapshot the app wrote.
  **Failure scenario:** combined with `X1`, one macOS widget refresh (which
  reads the wrong, empty store) blanks **all** desktop widgets. On iOS this
  manifests as a stale-read race that prunes freshly-written snapshots.

### High (26)

#### Stores/persistence

- **`H1` ✓ — RecurrenceSpawner assigns every spawn `seed.position + 0.5`**
  (`RecurrenceSpawner.swift:46`) — a guaranteed sibling-position collision on
  the second spawn from the same seed; also collides with reorder-heal
  output.
- **`H2` ✓ — Soft-delete/restore reconcile OS notifications for the root task
  only.** Cascaded descendants keep pending notifications (which then fire
  for a trashed task) or lose them on restore
  (`TaskStore.swift:726-728,745-747`).
- **`H3` — Hard delete/purge never cancels pending OS notifications.** A
  purged task's reminder fires later anyway, and its deep link dangles
  (`hardDelete`, `purgeAll`, `AutoPurgeJob`).
- **`H4` — `nextPositionDetail` counts trashed siblings, but recompaction
  excludes them** — restoring a task can land two live siblings on the exact
  same fractional position (`TaskStore.swift:987-1076`).
- **`H5` — Five stores never roll back failed mutations on the shared
  `viewContext`** (Tag/SmartFilter/Journal/Attachment/Series/Preferences) — a
  later, unrelated `save()` from any store commits the half-built rows;
  meanwhile `TaskStore`'s own rollback is unconditional and can discard other
  stores' legitimately staged work sharing the same context.
- **`H6` — RemoteChangeReconciler advances the history watermark before/
  regardless of work success** (`RemoteChangeReconciler.swift:124-135`) — a
  reconcile that fails for any reason is lost **permanently**, since the
  watermark has already moved past it. Contrast: `LocalBackupCoordinator`
  gets this right (advances only after successful apply) — the pattern to
  copy.
- **`H7` — Parent-cycle vulnerability.** Property-level CloudKit merge can
  create `X.parent = Y, Y.parent = X`. Every ancestor/descendant walk
  *except* `CascadeReaper` lacks a cycle guard, risking a main-thread hang or
  stack overflow — and `wouldCreateCycle` itself spins on a cycle rather than
  detecting it (`Validators.swift:8-17`, `applySoftDelete`, `deepCopy`,
  breadcrumb recording).

#### Sync machinery

- **`S5` — `syncFirstThenDisable` is identical to `disableNow`.** No quiesce
  wait fires when the target mode is `localOnly`; "sync one final time
  first" never actually syncs, and unexported edits are stranded on the
  device forever.
- **`S6` — Zone erase runs *after* mirroring re-attaches, with no post-erase
  re-seed.** Remote data can merge back in before the erase completes, and
  export metadata may already believe the (about to be erased) rows were
  uploaded — leaving iCloud either empty or a *union*, never the intended
  replacement. Contrast: `DataStoreResetService` erases while fully torn
  down, then rebuilds — the correct ordering.
- **`S7` — The quarantine "recovery anchor" is copied from a re-opened,
  WAL-active store.** The swap re-adds the same URL *before* the copy runs
  three non-atomic `copyItem` calls — the resulting backup can be torn, and
  may already contain merged remote data it was supposed to predate.
- **`S8` — `SyncModeStore` advances before destructive work runs, and is
  never reverted on failure.** "Try Again" only clears the journal. A failed
  `replaceICloudWithLocal` leaves mirroring live and actively merging, while
  the mode store claims the operation succeeded.
- **`S9a` — Reset/reseed drops all attachments.** `resetAndReseedFromThisDevice`
  calls `importBundle` without an `assetsDirectory`; the Importer's
  attachment-restore branch is gated on that parameter being present.
  (`BackupRestoreService` passes it correctly — this is a divergence between
  two callers of the same import path, not a fundamental import limitation.)
- **`S9b` — Crash mid-reseed is total local loss.** The reseed sequence is
  export → wipe → import with **no journal** and a temp-dir bundle; a crash
  at any point after the wipe leaves nothing to recover from.
- **`S9c` — Reseed broadcast fires before re-export quiesces.** Peers that
  receive the "reseed complete" signal and redownload immediately can pull a
  **partial** zone, mid-upload.
- **`S10` — Stale reset events apply unconditionally.** A peer offline for
  months applies a January "Reset Everywhere" event the moment it reconnects
  in July, destroying six months of offline work — `requestedAt` is never
  read, and there is no expiry or user confirmation. Separately, a
  local-only peer that receives the event retries it **forever** (apply
  throws on wrong mode) and never acknowledges receipt.
  **Product decision (Mikey, 2026-07-28):** remote reset events are **never
  auto-applied** — the receiving device always prompts the user before
  applying. See *Product decisions* below.
- **`S11` — Migration and reset can run concurrently.** Each service has its
  own reentrancy guard, but both operate on the same `PersistenceHost`;
  `ResetSignalMonitor` is fully automatic and migration-unaware, so
  `tearDownStore` can race `flushAndSwap`'s critical section.
- **`S12` — A failed `rebuildEmptyStore` leaves a store-less coordinator.**
  Unlike the zone-erase failure path, there is no reattach handler on this
  step — every fetch and save fails until the next relaunch. Related:
  `flushAndSwap` can silently "succeed" with zero attached stores and still
  advance `currentMode`.
- **`S13` — `AccountStateMonitor.refresh()` runs exactly once per launch.**
  A mid-session iCloud sign-out is never detected — the sync badge stays
  green and every probe keeps returning stale account state.

#### Cross-process / time-based

- **`X6` — Widget snapshots never regenerate on the app's own local writes.**
  Registration is on `NSPersistentStoreRemoteChange` only, which does not
  fire for same-coordinator saves (a macOS source comment asserts the
  opposite — it's wrong). The widget is permanently stale in `localOnly`
  mode; the 30-minute backstop just re-reads the same stale JSON.
- **`X7` — Recurrence spawn has no idempotency key.** `nextOccurrenceAfter`
  is the only guard, and the trump merge policy lets a concurrent widget/app
  interaction, or two devices closing the same task near-simultaneously,
  double-spawn the identical occurrence under distinct IDs — the reconciler
  has no way to collapse them. `RecurrenceLog` is an `os.Logger` call, not a
  ledger.
- **`X8` — Widget/Shortcuts/ShareExt task transitions never touch
  `notificationScheduler`.** Scheduler injection happens only in the two
  apps' composition roots. Completing a task from the widget leaves its
  reminder pending forever; recurrence spawns created from those paths
  schedule nothing.
- **`X9` — Cross-device notification-spec changes are never reconciled.**
  `RemoteChangeReconciler` filters to `lastFiredAt` changes only — spec
  inserts, spec deletes, and task soft-deletes made on another device leave
  local OS notifications wrong in **both** directions.
  `restoreSteadyState` runs only during migration, never on ordinary sync.
- **`X10` — The all-day scheduler default is hardcoded 09:00 at
  construction, never hydrated from user preferences at launch** — and
  worse, the reconcile pass actively **rewrites correct pending triggers
  back to 09:00**. Compounding: per-device `timeZone` defeats cross-device
  all-day dedup, so both devices fire.
- **`X11` — History-token watermarks survive store destroy/rebuild.** After
  any reset, all three watermark consumers resume from a token belonging to
  a store that no longer exists — silently deaf (nothing to consume) or a
  full unbounded replay, with no error surfaced either way. Reset also never
  clears the widget snapshot cache, so erased tasks keep rendering with
  dangling deep links.
- **`X12` — The `HistoryPruner` ordering trap is now real, not latent.** It
  runs after `autoPurge` on the design premise that "nothing consumes
  history in `localOnly` mode" — false: the backup coordinator only catches
  up via history observers, so share-extension writes made while the main
  app is closed can be pruned before the backup consumer ever sees them.
  (Corroborates `L7` — upgrades its severity from latent to real.)
- **`X13` — `.skipExisting` import still rewrites parents.** The second pass
  re-parents existing tasks even when told to skip them; a missing bundle
  parent silently promotes the child to root.

### Medium (25)

#### Stores/persistence

- **`M1` — Reparent/create/reorder all accept a soft-deleted parent**
  (`TaskStore.swift:322, 152, 500`) — creates the `C2` orphan state directly,
  with no soft-delete check at any of the three entry points.
- **`M2` — Archived + trashed can coexist; restore never clears
  `archivedAt`** — a restored task is invisible in every filter surface
  (`TaskStore.swift:669-754`).
- **`M3` — Both remote-change reconcilers are re-entrant per notification** —
  duplicate passes, watermark regression, and main-queue full-table-scan
  thrash under bursty remote-change delivery.
- **`M4` — `PreferencesStore.read()` performs writes.**
  `fetchOrCreateSingleton` saves inside a nominal read path, and
  `normalizeSingletons` can promote a stale legacy row over the canonical
  singleton (~32% of legacy UUIDs sort below the fixed singleton ID by raw
  byte comparison).
- **`M5` — `TaskDuplicateReconciler` swallows all errors and saves the
  shared `viewContext`** — failures are invisible, and the save can commit
  unrelated pending work from other stores (see `H5`/`X19`).
- **`M6` — `reorder` with `.explicit(parent)` plus a single anchor drawn
  from a different sibling group computes the new position from the wrong
  group** (`TaskStore.swift:409-413`).
- **`M7` — `AttachmentStore.delete` orphans its auto-created
  `JournalEntry`** (a Nullify relationship) — `JournalStore` refuses to
  delete auto-created entries as "non-user-editable," leaving a permanent
  blank journal row.

#### Sync machinery

- **`S14` — `waitForQuiesce`'s result is discarded** — a 300-second timeout
  is reported as success. Separately, quiesce can declare "settled" before
  sync has even started (`.setup` events don't bump the quiet window), and
  the single shared monitor interleaves multiple concurrent waiters.
- **`S15` — A corrupt or unparseable journal reads as `.idle`** (fail-open)
  in both `MigrationGate` and the coordinator's own reentrancy guard.
- **`S16` — Fresh-crash recovery has no UI affordance.** The recovery sheet
  only appears for *stale* (>600s) journals, but `MigrationGate` blocks
  extensions on **any** non-idle journal — extensions are bricked for up to
  600+ seconds with nothing telling the user why. The main app never
  consults the gate at all.
- **`S17` — The iCloud-unavailable launch screen performs an ungated,
  unjournaled mode swap with reversed step ordering** (`setMode` runs before
  `reconfigure`, everywhere else it's the other way around).
- **`S18` — `QuarantineManager.cleanupExpired()` is never called in
  production** — store copies accumulate unbounded until disk-full failure
  starts taking down every future migration; folder names also collide at
  1-second granularity.
- **`S19` — A partial zone-erase failure is not resumable** — "Try Again"
  never re-runs the erase step. `CloudKitErrorClassifier` lacks
  `zoneNotFound`/`userDeletedZone` cases, leaving a permanent red sync badge
  with no re-upload path. There is also no "iCloud not empty" guard before a
  `replaceLocal` direction proceeds.
- **`S20` — `ResetPropagator.broadcast` silently no-ops on a cold KVS
  roster** (e.g. a fresh install) — "Erase everywhere" wipes local data and
  the zone, notifies nobody, and reports success regardless.
- **`S21` — `SyncStatusMonitor`'s stall state is never cleared by swap or
  reset**, and import-side recoverable failures never escalate — the same
  failure class issue #66 named, now on the import axis.
- **`S22` — `ResetSignalMonitor.isApplying` is an unsynchronized `bool`
  touched from nonisolated `Task`s** (a real race, damage capped by a
  downstream guard). `ControlInbox` silently discards undecodable events
  forever, and `AppliedEventStore` grows unbounded.
- **`S23` — Backup correctness gaps:** the restore schema gate trusts the
  manifest over the actual records (needs a min-over-records check); the
  snapshot zips a directory that may be concurrently written (manifest
  `taskCount` and the real record count can disagree); and a reset destroys
  the *live* backup package via prune, leaving recovery dependent on a
  ≤24-hour-old zip.
- **`S24` — `PauseReasonClassifier`'s `.noNetwork`/`.iCloudDriveDisabled`/
  `.unknown` cases are unreachable** — the network monitor is hardcoded
  reachable and its setter is never called.

##### Sync test-coverage gaps (from this sweep)

No test asserts *what data ends up where* after either replace direction; no
behavioral test distinguishes `syncFirst` from `now`; and no test covers
restore with `previousMode == currentMode`, failed-migration mode-store
state, migration↔reset concurrency, a throwing `rebuildEmptyStore`,
attachment survival through reseed, account transitions, or `.timedOut`
quiesce reactions.

#### Cross-process / time-based

- **`X14` — `AutoPurge` deletes by a stale `objectID` with no re-validation
  at delete time** — it can consume a task that was restored mid-flight
  (which `X4` then resurrects from the zone).
- **`X15` — Five processes each stand up their own
  `NSPersistentCloudKitContainer` with mirroring active on one shared store
  file** — the widget process operates under a ~30MB memory budget the
  engineering notes already flag as unaffordable for this.
- **`X16` — `AfterCompletionRule.interval` is unvalidated** — `CalendarRule`
  has a clamp, this sibling rule does not; a `0`/negative interval spawns
  permanently-overdue tasks on every close.
- **`X17` — Weekly `byDay` recurrence hardcodes a Sunday week boundary** — a
  biweekly Saturday/Sunday recurrence silently skips occurrences in
  Monday-first locales.
- **`X18` — Export performs 4 independent fetches against a live-mirroring
  store with no quiesce**, producing a torn bundle (orphan journal entries
  the importer then drops — permanently, via `S9b`'s reseed path).
- **`X19` — `viewContext` saves from read/maintenance paths**
  (`PreferencesStore.read`, `NotificationSpecStore`,
  `TaskDuplicateReconciler`) commit unrelated pending edits from whatever
  else happens to be staged on the shared context.
- **`X20` — `AppPreferences` double-create race across processes/devices**
  — the normalize tie-break is nondeterministic on identical `singletonID`
  rows, causing an observable flip-flop that can reopen after appearing
  resolved.

##### Structural test gaps (cross-process sweep — why these survived)

**No multi-process test exists** — nothing in the suite opens two
`PersistenceController`s against one store file. `X1`, `X2`, `X5`, `X7`,
`X15`, and `X20` are invisible by construction under the current test
architecture. There is also no test pinning the App Group store path across
processes, no export→import completeness round-trip (series/specs/
archivedAt), no `RecurrenceSpawner`-specific suite (let alone
locale-parameterized recurrence tests), and no test asserting a widget
refresh follows the app's own local write, or that a reset clears the widget
cache and history watermarks.

### Low (7)

All from the stores/persistence sweep — neither the sync nor cross-process
sweep produced a distinct Low tier (their lowest-severity findings sit at
Medium above).

- **`L1` — Smart-filter sort tie-break uses raw-byte UUID comparison,
  contradicting `SiblingOrder`'s canonical order** — the same rows render in
  opposite order on different surfaces.
- **`L2` — `installDefaultsIfNeeded` has a cross-process check-then-act
  race** — produces duplicate default filters until the next dedupe pass.
- **`L3` — `syncCounts` materializes all task IDs on the `viewContext`** —
  unbounded main-queue work as the task count grows.
- **`L4` — `unassignTag` writes unconditionally** — a spurious
  `modifiedAt` bump and CloudKit export even when nothing changed.
- **`L5` — `archive`/`unarchive` fail the *whole* batch on one missing ID** —
  no partial-success path.
- **`L6` — `Series.rule`'s setter nils the rule on encode failure** —
  symptom-masking `try?` that silently drops recurrence data instead of
  surfacing the encode error.
- **`L7` — `HistoryPruner` prunes to the current token, not the minimum
  consumer watermark** — safe today only by bootstrap ordering; a latent
  trap corroborated and upgraded to a real, reachable defect by `X12`. Its
  written `tokenDefaultsKey` is never read by anything.

---

## Existing mitigations verified sound (do not touch)

Spot-checked during this sweep and confirmed still correct as of
2026-07-28 — these are load-bearing patterns from the 2026-05-28 Foundation
Hardening program; remediation work must not regress them:

- `PersistenceHost.flushAndSwap`'s single-`perform` critical section with
  rollback-re-add preserving `cloudKitContainerOptions`, and its hard guard
  on synchronous store add.
- `TagStore.findOrCreate`'s atomicity within one `perform`.
- The reorder heal/throw split plus its stress tests; `localTaskRowCount`
  fails closed.
- `LocalBackupCoordinator` advances its watermark **only after** a
  successful apply — this is the correct pattern that `H6` violates
  elsewhere; copy it, don't reinvent it.
- `rollback()` cannot discard CloudKit imports, because those are already
  committed to the store rather than pending in the context being rolled
  back.

## Product decisions

Two findings required a product call rather than a purely technical fix.
Both were decided by Mikey on 2026-07-28 and are binding for the
remediation program (Wave 1 and Wave 3 respectively):

- **`C2` — restoring a child whose parent is still trashed PROMOTES IT TO
  ROOT.** Restoring a task severs its link to a still-trashed parent rather
  than leaving it in the unreachable, `C1`-vulnerable limbo state it's in
  today. The user gets their task back, visible, at the top level; they can
  manually re-parent it if the original parent is later restored too.
- **`S10` — remote reset events are NEVER auto-applied.** The receiving
  device always prompts the user before applying a "Reset Everywhere" (or
  similar) event from another device, regardless of the event's age. An
  expiry window is still worth keeping as a hygiene bound for abandoned
  events (so a five-year-old event doesn't sit in a prompt forever) — the
  exact window is a council-vote decision left to Wave 3.

## Mikey's manual-verification checklist

These require a live iCloud account, a second Apple ID, or physical devices
— none of them gate the corresponding fix, and none are silently dropped.
The **living, checkable copy of this list** is in the ledger index
(`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`); this copy
is a point-in-time reference.

- [ ] CloudKit Console: audit the Production zone for orphaned/purged
      records (`C4`/`X4`) — once, at leisure; re-check after Wave 1's
      `purge-cloudkit-retirement` plan merges and deploys.
- [ ] macOS pre/post store-location migration with data intact (Wave 1c).
- [ ] End-to-end sync-mode switches on live iCloud (Wave 2).
- [ ] Account switch with a second Apple ID (Wave 3).
- [ ] Two-device reset propagation, including the stale-event UX (Wave 3).
- [ ] Real-widget verification: completing a task cancels its reminder;
      a local edit refreshes the widget (Waves 4-5).
- [ ] If Wave 1d adds any new CloudKit record types/fields: a standing
      Development → Production schema deploy in the Console is required
      before a Production build can use them.
- [ ] iCloud-dependent app-hosted/UI tests — standing CI-scope rule; these
      are verified manually per wave, same as the Foundation Hardening
      program.

---

*Remediation program (waves, plans, story assignments, shared-file serial
chains, resume protocol): see
[`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`](../superpowers/plans/2026-07-28-data-sync-hardening-index.md).*
