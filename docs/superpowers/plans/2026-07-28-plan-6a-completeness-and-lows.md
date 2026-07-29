# Plan 6a — completeness-and-lows (Wave 6, program closeout)

Findings: `L1`, `L2`, `L6`. Stories: `LIL-70`, `LIL-71`, `LIL-75`. Plus the
six discovered-during-earlier-waves residuals this wave's brief folded in
(`LIL-77`, `LIL-80`, `LIL-81`, `LIL-82`, `LIL-84`, `LIL-87`), two more
residuals discovered *during this wave's own* completeness-proof tests
(`LIL-88`, `LIL-89`), one latent residual confirmed still correctly deferred
(`LIL-90`), and two completeness-proof test suites the wave brief calls for
directly (export/import round-trip equality; the `X20` flip-flop stress).
Review doc: `docs/reviews/2026-07-28-data-sync-review.md`. Ledger:
`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`.

Hotspots: `Stores/SmartFilterStore+Defaults.swift`,
`ManagedObjects/Series+CoreData.swift`, `Stores/SeriesStore.swift`,
`Export/Importer.swift`, `Export/ExportSchema.swift`,
`Sync/MigrationCoordinator.swift`, `Sync/DataStoreResetService.swift`,
`Backup/LocalBackupCoordinator.swift`, `Sync/SyncQuiesceMonitor.swift`,
`Recurrence/X16AfterCompletionIntervalClampTests.swift`,
`Widgets/WidgetRefreshController.swift` (test-only),
`Persistence/PreferencesStoreSingletonTests.swift` (test-only),
`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`,
`Apps/Lillist-macOS/Sources/AppEnvironment.swift`,
`Apps/Lillist-iOS/Sources/Settings/CrashReportingSection.swift`,
`Apps/Lillist-macOS/Sources/Preferences/CrashReportingPane.swift`,
`Apps/Lillist-iOS/Sources/Tasks/TasksView.swift`,
`Apps/Lillist-macOS/Sources/Tasks/MacTasksView.swift`,
`Packages/LillistUI/Sources/LillistUI/iOS/Tasks/FilterHeader.swift`.

This is the program's last wave: a completeness sweep across the whole
70-finding program rather than one cohesive architectural design, so this
plan doc is organized as one section per item rather than one continuous
narrative. Every serial chain the ledger tracks (`TaskStore.swift`,
`MigrationCoordinator.swift`, `PersistenceHost.swift`,
`RemoteChangeReconciler.swift`, `AppEnvironment.swift`,
`HistoryPruner.swift` + watermarks, `Importer`/`Exporter`/schema) was
already closed by the time this wave started (see `5c`'s closing report's
"What Wave 6 needs to know" — every chain reads "no further work
scheduled"), so none of this wave's fixes needed to re-open one.

## 1. `L1` — pinned filter chip row uses canonical `SiblingOrder`

**Where the finding actually lives.** `SmartFilterStore.list()` (the
store-layer sort) already used `SiblingOrder.precedes` — introduced by a
pre-program commit (`056be53e`), unrelated to this review. The live
instance of `L1` was in the APP layer: `TasksView.swift` (iOS) and
`MacTasksView.swift` (macOS) both independently computed their pinned-filter
chip row as

```swift
savedFilters.filter { $0.isPinned }.sorted { $0.position < $1.position }
```

— a raw position comparator with no tie-break, discarding whatever order
`list()`'s own `SiblingOrder` sort had already established. Two pinned
filters sharing a position (a real, reachable state before
`normalizeIfDegenerate()`'s next pass, or mid-CloudKit-merge) could render in
a different relative order on the chip row than on the Settings/Preferences
surface.

**Fix.** Consolidated the duplicated per-app logic into
`SavedFilterChipSpec.pinnedSorted(from:)` in `LillistUI` (`FilterHeader.swift`,
next to the type it returns) — both apps now call the one shared,
`nonisolated static` helper. This closes the duplication AND makes the sort
directly unit-testable (`SavedFilterChipSpecOrderingTests`, LillistUI), which
neither app-target `View`'s own computed property ever could have been —
closing the "no host-side unit test target reaches this" gap that purely
app-target UI fixes elsewhere in this program had to accept as a limitation.

**No council needed** — this is the same, already-established `SiblingOrder`
pattern used everywhere else in the codebase; there was no second defensible
tie-break to weigh.

## 2. `L2` — `installDefaultsIfNeeded`'s self-heal actually runs on every launch

**The gap.** `SmartFilterStore.deduplicateExactDuplicates()`'s own doc
comment claims cross-device create races "self-heal across launches" — but
`installDefaultsIfNeeded()` (which begins with this same dedup pass) is
called **only from onboarding**, a one-time, first-launch entry point
(`DefaultsInstaller.installIfNeeded()`, wired from `OnboardingScreen`/
`OnboardingSheet` only). A device that completed onboarding before a
cross-device race landed a duplicate would never run the dedup pass again —
the doc comment's claim was aspirational, not actual, for any device past
its first launch.

**Fix.** Both `AppEnvironment.bootstrap()`s now call
`smartFilterStore.deduplicateExactDuplicates()` directly, alongside the other
cross-process self-heal steps (`taskDuplicateReconciler.reconcileNow()`,
`TreeIntegrityChecker.repair`) — making every ordinary launch a genuine
self-heal opportunity, matching the doc comment's actual claim rather than
narrowing its scope to match reality.

**No new unit test possible** — the method being called
(`deduplicateExactDuplicates()`) is already covered elsewhere; the only
change here is a bootstrap call site, the same "no host-side unit test
target reaches `AppEnvironment.bootstrap()`'s private launch sequence"
limitation `2a`'s `S16`/`S17` and `3a`'s app wiring already accepted.
Verified via unsigned `xcodebuild build` for both apps.

## 3. `L6` — `Series.rule` throws on encode failure instead of silently nil-ing

**The anti-pattern.** `Series.rule`'s setter used `try?` and fell back to
`ruleJSON = nil` on any encode failure — silently and permanently dropping a
series' recurrence data with no signal, unlike this codebase's own sibling
JSON-column pattern (`SmartFilterStore.encode(_:)`/`.decode(_:)`, which
already throws for the structurally-analogous `PredicateGroup` column).

**Reachability, traced precisely (not assumed).** `RecurrenceRule`'s two
concrete cases (`CalendarRule`, `AfterCompletionRule`) both normalize their
`interval` fields at construction AND at the point-of-use expander call
(the `X16`/pre-existing `CalendarRule` clamps — defense in depth, verified
via `Swift.max`/`Swift.min`'s actual NaN/infinity semantics: a non-finite
raw value collapses to the clamp's own minimum, not to NaN). Every other
field is a plain `String`-raw enum, `Int`, or optional `Date` — none of
which `JSONEncoder` can fail to encode. **A genuinely encode-failing
`RecurrenceRule` cannot be constructed through any public API today** — this
finding's failure mode is a real anti-pattern (the swallow), not a currently
reachable data-loss path. Matches this program's own precedent for
defense-in-depth fixes whose triggering condition is bounded/theoretical
(e.g. `4a`'s `transactionAuthor` fix, `5c`'s "watermark not locatable"
case) — the fix is warranted by the PATTERN, not by a live reproduction.

**Fix.** `rule` is now a get-only computed property; a new throwing
`setRule(_:)` method replaces the setter, encoding first and only assigning
`ruleJSON` on success — a failure can never overwrite a previously-valid
rule with `nil`. All four call sites (`SeriesStore.create`/`update`/
`forkFutureFromInstance`, `Importer.applySeries`) already ran inside
throwing contexts (`withMutationRollback` closures, or a per-row
`do`/`catch` that already collects errors for every other entity) — the
`try` addition was a mechanical propagation, not a new error-handling shape.

**Regression coverage for an unreachable failure mode.** Since no public
`RecurrenceRule` value can trigger the encode-failure branch, the
regression proof is structural rather than a repro: `setRule` round-trips a
valid rule correctly (positive-path pin), plus a source-text conformance
test (mirroring `5a`'s `MutationRollbackConformanceTests`/`5c`'s
`WatermarkRegistryConformanceTests` precedent) asserting `Series+CoreData.swift`
contains no `try? JSONEncoder().encode` and no reintroduced `set {}` on
`rule` — a genuine red→green test for THIS finding specifically (it fails
red against the pre-fix source, verified by construction: the pre-fix file
literally contained the string the test asserts is absent).

## 4. `LIL-77` — crash-prompt toggle persists to the wrong store

**The gap (discovered during `1d`, filed then, fixed here).**
`CrashReportingSection` (iOS) / `CrashReportingPane` (macOS) bound the
Settings toggle to `PreferencesStore.Prefs.crashPromptsEnabled` — the
shared, CloudKit-synced Core Data field — and persisted via
`preferencesStore.update`. But `AppEnvironment.crashPromptsEnabled` (what
`CrashReporterHost` actually reads at boot) initializes from
`DevicePreferencesStore`, the Plan-21 device-local partition this toggle
never touched. A user's choice could silently revert on the next relaunch.

**Why this is squarely a "toggle bound to the wrong store" bug, not a
partition-design question.** `AppPreferencesPartitionMigrator`'s own doc
comment says the Core Data copy of these five fields is kept only for
"legacy code paths that have not yet migrated" — `DiagnosticsSection`/
`DiagnosticsPane` had already migrated (device-local `@State` + `.task`
hydration + write-through `Binding`, matching `diagnosticLoggingEnabled`'s
identical shape); `CrashReportingSection`/`CrashReportingPane` simply
hadn't yet.

**Fix.** Both toggles now hydrate from and persist directly to
`DevicePreferencesStore.crashPromptsEnabled()`/`.setCrashPromptsEnabled(_:)`,
mirroring `DiagnosticsPane`'s exact pattern byte-for-byte (down to the
`didHydrate` guard that stops a delayed `.task` hydration from clobbering a
user tap that already landed). `DebugPage`/`SettingsTab` no longer thread a
`Prefs` binding through to this section — it's now fully self-contained,
like `DiagnosticsSection` already was. The Core Data field itself, its
export/backup mapping, and `AppPreferencesPartitionMigrator` are untouched
(per that type's own doc comment: "eliminating the attributes can wait for
a future model version bump" — out of this fix's scope and this program's
zero-CloudKit-schema-change posture).

**Verification:** unsigned `xcodebuild build` for both apps only — same
"no host-side unit test target reaches SwiftUI view state" limitation as
`L2` above.

## 5. `LIL-80` / `LIL-81` — `restoreFromBackup`'s two account/backup gaps

Both findings live in the same method
(`MigrationCoordinator.restoreFromBackup` — the raw-SQLite
migration-crash-recovery restore, a DIFFERENT subsystem from
`BackupRestoreService`'s JSON-package restore), fixed together since they're
adjacent edits to the same short function.

**`LIL-80` (discovered during `2b`).** `restoreFromBackup` swaps the live
SQLite file directly with `quarantine.restore(...)` — no Core Data save, so
`LocalBackupCoordinator`'s two observers (`NSManagedObjectContextDidSave`/
`NSPersistentStoreRemoteChange`) never fire, leaving the live JSON backup
package describing the pre-restore store. `2b`'s `S23` fix already solved
the identical shape for the JSON-package restore subsystem via
`BackupPackageReconciling`; `restoreFromBackup` just never got the same
treatment (`2b`'s own closing report flagged this gap for a future plan).
**Fix:** reused the existing `BackupPackageReconciling` protocol —
`restoreFromBackup` gained a `backupReconciler` constructor parameter,
called on the successful-completion path only (same "only on success"
discipline every other reset-adjacent closure on this type already follows),
wired to `localBackupCoordinator` in both `AppEnvironment`s.

**`LIL-81` (discovered during `3a`).** `3a` added an account-changed
pre-flight to `runMigration`'s four ops but explicitly left
`restoreFromBackup` unguarded (`3a`'s own closing report: "consider whether
it needs one before `3a` lands its own probe elsewhere" — traced, then
filed rather than expanding an already-large plan). The narrow compound
scenario: a migration crashes, the account changes before the user triggers
recovery, and `previousMode == .iCloudSync` — the restore would reattach
with mirroring armed against the new account. **Fix:** the identical guard
shape `runMigration`'s ops already use, placed after the recovery-anchor
`tearDownStore` (unaffected) but before `attachStore(at: prev)`, gated to
`prev == .iCloudSync` (a `.localOnly` reattach arms no mirroring
regardless — proven by a dedicated test showing the guard does NOT fire for
that mode even when the provider reports `.accountChanged`).

**No council needed for either** — both are direct extensions of an
already-established, already-council-vetted pattern (`S23`'s
`BackupPackageReconciling` chokepoint; `3a`'s account-changed preflight
shape) to a sibling call site the original plan explicitly deferred.

## 6. `LIL-82` — `TaskDuplicateReconciler.diagnosticLog` wiring

Mechanical: `1a`'s `M5` fix added the property, `4a`'s `H6` fix wired the
IDENTICAL property on `RemoteChangeReconciler` in both apps, but nobody ever
wired `TaskDuplicateReconciler`'s copy. One assignment per app, placed
immediately after `remoteChangeReconciler.diagnosticLog`'s existing
assignment (iOS) / immediately after `taskDuplicateReconciler`'s own
construction, which on macOS already runs after `diagnosticLog` exists.

## 7. `LIL-84` — three named timing flakes, three shape-appropriate fixes

See the ledger's `LIL-84` story comments for the exact three named
instances (the quiesce pair, the `X16` boundary, `5b`'s widget debounce
test) and the commit message for the full per-item design. Summary:

- **The quiesce pair** (`SyncQuiesceMonitorTests.timesOutWhenChurning`/
  `setupEventsCountAsActivity`): extracted the ONE comparison
  `waitForQuiesce`'s poll loop makes every tick into a named
  `QuiesceDecision.isQuiesced` — a pure, zero-behavior-change refactor
  (production's `Date()`/`Task.sleep`/deadline structure is byte-identical
  to before; only the inline boolean expression got a name). New
  `SyncQuiesceDecisionTests` drives that same function through a synthetic
  simulation loop (a caller-supplied event-offset schedule instead of a
  real `CloudKitEventBridge`), proving the full S14 poll-loop shape with
  zero real elapsed time. The original real-clock tests are unchanged,
  kept as integration smoke checks.
- **The `X16` boundary** (`spawnedInstanceIsNeverOverdueOnCreation`):
  the assertion compared `spawn.start` against a `Date()` the test captured
  independently before calling `transition()` — racing however long
  `transition`'s own `context.perform` took to actually run under
  contention. Now compares against the seed task's own PERSISTED
  `closedAt` (fetched back after the transition) — `spawn.start` is
  derived directly from `closedAt`, so comparing against the SAME value
  removes the independent-`Date()`-sampling race entirely, a strictly
  more correct test regardless of the exact contention mechanics.
- **`5b`'s widget debounce test** (`burstOfSavesDebouncesToOneReload`):
  widened the debounce window (100ms → 500ms) and shrank the inter-save
  gap (20ms → 5ms), ~5x → ~20x headroom. The mechanism this test proves
  (a burst of saves coalesces into one rebuild) is unchanged; only the
  timing margin needed more slack than `5b`'s own two prior hardening
  passes anticipated (per `5c`'s closing report, which hit this same test
  flake a third time under a heavily-contended machine).

## 8. `LIL-87` — `LocalBackupCoordinator` launch-time history catch-up

**The gap (discovered during `5c`).** Unlike `RemoteChangeReconciler`/
`DiagnosticHistoryObserver`, `LocalBackupCoordinator.bootstrapAtLaunch()`
never called `processRemoteChange()` as an explicit catch-up — it only ever
advanced its watermark from a LIVE notification firing while the app
happened to be running. `5c`'s registry-gated `HistoryPruner` already
prevents the *data-loss* consequence (a stale watermark blocks the prune
sweep instead of silently pruning past it), but the underlying staleness
was real: with nothing to prompt it, the watermark — and therefore pruning
— could stall indefinitely.

**Fix.** `bootstrapAtLaunch()` now calls `processRemoteChange()` before
`start()`, mirroring every other history consumer's catch-up-then-start
shape exactly.

**Regression test, and why the first attempt was wrong.** A first version
of the test wrote a foreign task to a shared store file, then called
`bootstrapAtLaunch()` on a coordinator over a STILL-EMPTY local package —
and it passed even against the pre-fix source, because a still-empty
package's `seedPackageIfEmpty()` does a FULL reconcile regardless of any
history catch-up, masking the fix entirely. Caught by actually reverting
the production change and re-running (the binding discipline this program
has followed throughout) — not assumed green. Redesigned to populate the
package on a first simulated "launch," tear that coordinator down, write a
foreign change while nothing observes, then construct a FRESH coordinator
(sharing the SAME token-store suite, simulating the SAME device's
persisted watermark across a relaunch) for the second "launch" —
`seedPackageIfEmpty()` is now guaranteed a no-op, isolating the explicit
catch-up as the only remaining mechanism that could pick up the foreign
change. Confirmed red against the reverted source, green against the fix.

## 9. Discovered during this wave's own tests

Two of this wave's three new completeness-proof test suites (see §11–12)
surfaced genuine, previously-undiscovered defects — exactly the outcome a
completeness sweep exists to catch. Both fixed in-session, filed as
stories per the `LIL-77`/`LIL-81` precedent (a genuine defect gets a story
even when found and fixed the same session, since "trivial same-session
finds" in `CLAUDE.md`'s sense means a typo-class fix, not a silent
cross-device data-loss bug).

### `LIL-88` — `Importer.apply` never restored `document.preferences`

The export round-trip equality test (§11) failed on its very first run:
`Importer.apply` had **zero** code touching `document.preferences` at all
— an export → wipe → import cycle (manual export/import in Settings, and
`resetAndReseedFromThisDevice()`) silently reverted every account-level
preference (trash retention, morning summary time, default tag tint, ...)
to its hardcoded default. Not a narrow edge case: this is the PRIMARY path
for restoring account settings alongside tasks/tags/series, and it simply
never ran.

**Fix.** New `Importer.applyPreferences(_:policy:ctx:)` restores the
document's preferences into the destination's singleton `AppPreferences`
row (creating it if absent). `AppPreferences` carries no `modifiedAt` (same
as `Series`/`Tag`), so there's no timestamp to arbitrate a `.recencyWins`
decision — follows their established "incoming wins" fallback for both
`.replaceExisting` and `.recencyWins`; `.skipExisting` only skips when a
row already exists to skip (an absent singleton has nothing to skip,
matching every other entity's "insert always happens, `.skipExisting` only
guards updates" shape). `ImportSummary` gained a `preferencesApplied: Bool`
field (additive, default `false`, source-compatible).

### `LIL-89` — `recoverInterruptedReseed` never broadcast to peers

Flagged as a residual in `3b`'s OWN closing report (not discovered fresh by
this wave — the ledger sweep in §13 below surfaced it): `S9c` made the
PRIMARY (non-crashed) `resetAndReseedFromThisDevice()` path wait for its
re-export to quiesce, then broadcast to peers; the CRASH-RECOVERY resume
branch (`recoverInterruptedReseed()`) never called `propagator?.broadcast`
at all, crashed-or-not. **Fix:** mirrors the primary path's exact
quiesce-then-broadcast shape after its existing reimport/`backupReconciler`/
`widgetCacheReset` steps.

## 10. `LIL-90` — confirmed still correctly deferred, not fixed

A remote `NotificationSpec.snoozedUntil`/`.offsetMinutes` in-place edit is
invisible to `RemoteChangeReconciler`'s diff — `4b`'s own plan doc already
traced this precisely (grep-confirmed `NotificationSpecStore.update` has
exactly one production caller, same-device only; no UI path edits an
existing spec in place) and declared it LATENT, not reachable, tracked debt
for "whichever future plan touches `NotificationSpecStore.update`'s
callers." Nothing changed that calculus during this wave (no new caller was
added). Filed as `LIL-90` (it had no story yet) so it's durably tracked,
left `todo`/deferred rather than fixed — adding a reconcile path for a
scenario nothing can currently trigger would be untested, unreachable code
for its own sake (YAGNI), not a completeness win.

## 11. Export/import round-trip equality suite

The wave brief's own ask, on top of `1d`'s two existing suites
(`ExportSchemaCompletenessTests`, model-derived field-mapping coverage;
`X3ExportSchemaCompletenessTests`, one export's field values). Neither
actually re-imports what it exported — an importer-side drop (as opposed to
a missing DTO mapping) would pass both and still be invisible. New
`ExportImportRoundTripEqualityTests`: build one fixture exercising every
entity kind (tagged parent/child tasks, an archived-and-closed task, a
journal entry + attachment with real bytes, a recurrence series + reminder,
a smart filter, a real synced preference), export → import into a
genuinely FRESH store (not the source store — proves the importer alone
reconstructs everything) → export again, then assert the two documents are
equal (dictionary-keyed by id, since import makes no array-order promise)
modulo `exportedAt` (a fresh timestamp by design). This is what caught
`LIL-88`.

## 12. `X20` flip-flop stress

`5a`'s `normalizeSingletons()` tie-break was already proven deterministic
across two independent in-memory stores
(`twoCanonicalRowsConvergeDeterministically`). The wave brief asks for the
stronger proof: two independently-constructed
`NSPersistentCloudKitContainer`s sharing ONE on-disk file (the
`MultiProcessStoreHarnessTests` keystone shape), racing
`normalizeSingletons()` against each other with real concurrency (`async
let`, not a scripted sequence) against a not-yet-converged store, then both
running the same convergence pass every device's own bootstrap performs —
repeated across 8 fresh store files in one test run, so a
non-deterministic tie-break would eventually disagree with itself even if
any single run looked clean. Stable across four consecutive manual runs
(~0.15–0.25s each) before landing.

## 13. Ledger residual sweep — close-vs-defer table

Every "Discovered, out-of-scope residual" / "flagged for Wave 6" /
"worth a future wave" note across all fourteen closing reports, decided:

| Residual | Source wave | Call | Why |
|---|---|---|---|
| `LIL-77` crash-prompt persistence | `1d` | **Closed** (§4) | Small, mechanical, well-understood store swap |
| `LIL-80` restoreFromBackup backup resync | `2b` | **Closed** (§5) | Reuses an existing chokepoint (`BackupPackageReconciling`) |
| `LIL-81` restoreFromBackup account guard | `3a` | **Closed** (§5) | Reuses an existing guard shape verbatim |
| `LIL-82` TaskDuplicateReconciler.diagnosticLog | `4a` | **Closed** (§6) | One-line wiring, zero design questions |
| `LIL-84` timing-flake family | orchestrator (post-`4b`) | **Closed** (§7) | Test-infra only; each instance individually small |
| `LIL-87` LocalBackupCoordinator catch-up | `5c` | **Closed** (§8) | Mirrors an existing, well-established pattern |
| `LIL-89` recoverInterruptedReseed broadcast | `3b` | **Closed** (§9) | Mirrors the primary reseed path's own already-shipped code, found during this wave's own sweep |
| `LIL-83` `X10` timezone-dedup posture | `4b` | **Deferred — explicit program decision** | Requires a new synced `AppPreferences` field → a Development→Production schema deploy Mikey must run; orchestrator decision (2026-07-29) to keep this program's zero-schema-change posture intact near its end. Interim discipline (design-doc note, `TODO(LIL-83)` markers, KNOWN LIMITATION test) already shipped in `4b`. Redesign trigger: a real user report of a cross-timezone duplicate notification, or Mikey scheduling the field work directly. |
| `LIL-90` NotificationSpec in-place edit reconcile gap | `4b` | **Deferred — latent, unreachable** | `4b`'s own plan doc already traced this precisely and declared it tracked debt; nothing changed that calculus. Fixing an unreachable path is speculative code, not a completeness win (YAGNI). Redesign trigger: any new `NotificationSpecStore.update` caller reachable from a different device/process. |
| `LIL-86` X10 timezone dedup date-dependency | `5a` | **Already closed within `5a` itself** | Ledger: "no `6a` action needed" |
| `LIL-79` `GatedPersistenceResolverTests` UserDefaults race | `1c` | **Already closed within `1c`'s own correction** | Fixed at discovery, verification protocol made binding program-wide |

No residual was silently dropped: every ledger mention above resolves to
either a landed fix in this plan or an explicit, reasoned defer with a
named redesign trigger — the same discipline the review doc's own
"Product decisions"/"Known constraints" sections established for the
program's two council-level decisions.

## 14. Verification

Full `LillistCore` suite green (unmasked exit code, clean grep for the
failure markers) after this plan's commits — see the ledger's final
closing-report entry for the exact run log and test-count delta from `5c`'s
1429/259 baseline. LillistUI non-snapshot suite green (the new
`SavedFilterChipSpecOrderingTests` suite included). `lillist-cli` builds.
Both apps verified with unsigned `xcodebuild` builds (BUILD SUCCEEDED)
after every app-touching commit (`L1`, `L2`, `LIL-77`, `LIL-80`/`LIL-81`).
`xcodegen generate` drift check clean for both `project.yml` specs.

No new CloudKit record types or fields were added by any fix in this plan
— every change is to in-process logic, the export/import file format
(`Importer.applyPreferences` writes into the EXISTING `AppPreferences`
Core Data attributes, none of them new), or test/app-target code. No
schema deploy is needed for this plan.
