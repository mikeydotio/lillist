# Plan 4b — Notification Truthfulness

**Wave:** 4 (second plan; follows `4a` `history-consumer-discipline`)
**Findings:** `H2`, `X8`, `X9`, `X10` (stories `LIL-20`, `LIL-39`, `LIL-40`, `LIL-41`)
**Review doc:** `docs/reviews/2026-07-28-data-sync-review.md`
**Ledger:** `docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`

This is the second plan in chain 4 (`RemoteChangeReconciler.swift`) and rejoins chain 1
(`TaskStore.swift`, last touched by `1b`) and chain 5 (`AppEnvironment.swift`, both
platforms, last touched by `3b`). It also opens new ground: this is the first plan in the
program to touch the `Extensions/` targets' own construction sites for notification
scheduling.

## Context all four findings share

Lillist's notification-truthfulness contract, as designed (`docs/plans/2026-05-12-lillist-design.md`
Section 4), is: "the set of pending OS-level notification requests always matches what
`NotificationScheduler.computeDesiredRequests` would compute from the current
`NotificationSpec`/`LillistTask` state." Every finding in this plan is a place that
contract silently breaks — descendants during trash/restore (`H2`), three whole
processes that mutate task/notification state without ever touching a scheduler (`X8`),
remote changes the local reconciler doesn't diff for (`X9`), and a default value that's
wrong at every cold launch (`X10`).

---

## H2 — cascade notification reconcile for softDelete/restore

**Finding:** `TaskStore.softDelete(id:)` and `TaskStore.restore(id:)` only call
`notificationScheduler?.reconcile(taskID: id)` for the ROOT id, even though both mutate
an entire subtree (`applySoftDelete`/`clearSoftDelete` already recurse into every
descendant, cascading `deletedAt`/`archivedAt`). A trashed subtree's descendants keep
firing (their spec rows are untouched, so `reconcile` would have computed `[]` for them —
but it's never called). A restored subtree's descendants never get their specs
re-installed (a descendant task's `deletedAt` clears, so `computeDesiredRequests` would
now return real requests for it — but again, `reconcile` is never called for it).

**Root cause, not symptom:** `applySoftDelete`/`clearSoftDelete`'s two-arity shape
(public wrapper + `visited: inout Set<NSManagedObjectID>` recursive worker, per `1a`'s
H7 cycle-guard fix) already walks the exact set of tasks each mutation touches — it just
throws that information away instead of returning it.

**Fix:** widen the `visited`-tracking worker to also collect the **task UUIDs** (not
just the `NSManagedObjectID`s already tracked for cycle-safety) of every node it visits,
and return that list from the public wrapper. `softDelete`/`restore` then reconcile using
that full set instead of just `id`:

- `softDelete`: `notificationScheduler?.cancelPending(forTaskIDs: affectedIDs)` — H3's
  batched cancellation primitive is the right shape here too (a trashed subtree's desired
  set is unconditionally `[]` for every member, so there's nothing to *compute*, only to
  *cancel* — one OS round trip regardless of subtree size, not O(N) `reconcile` calls).
- `restore`: `for id in affectedIDs { await notificationScheduler?.reconcile(taskID: id) }`
  — restore needs real re-computation (a descendant may have specs whose fire dates are
  still in the future), so the batched cancel-only primitive doesn't apply; this mirrors
  `transition`'s existing sequential-reconcile-per-id pattern for `spawnedID`.

**Two-hats:** this is a pure behavior fix (no refactor bundled) — the `visited`-set
change is additive (new accumulator parameter alongside the existing one), not a
restructuring of the cascade walk itself.

---

## X8 — extension processes never touch a notification scheduler

**Finding:** `AdvanceTaskStatusFromWidget` (widget), `CompleteTaskIntent`/
`ToggleStatusIntent`/`AddNudgeIntent` (Shortcuts/App Intents), and `ShareRootView`
(Share Extension) all construct a bare `TaskStore(persistence:)` (or, for the two status
intents, route through `CLIBridge.StatusHandler.run`) with no `notificationScheduler`
ever assigned. Completing a task from the widget leaves its reminder pending; adding a
nudge from Shortcuts persists the spec but never installs a `UNNotificationRequest`.

### Investigation: can these processes actually use `UNUserNotificationCenter`?

Yes — confirmed, not assumed. `UNUserNotificationCenter` notification state (both
pending-request scheduling and authorization status) is scoped to the **top-level
containing app's bundle**, shared automatically by every app extension in that app's
group; extensions don't need (and can't request) their own separate authorization. The
three target extensions here are exactly the kind of extension Apple documents as able to
call `add(_:)`/`removePendingNotificationRequests(withIdentifiers:)` freely once the
containing app (Lillist) has been granted notification authorization — no new
entitlement, no new capability declaration needed (there is already precedent:
`AdvanceTaskStatusFromWidget` already imports `WidgetKit` and manipulates
`WidgetCenter`/App-Group state from the widget process without incident).

`X15`'s "~30MB widget memory budget" constraint (cited by the ledger's wave-4a handoff as
a reason to double-check before adding anything to the widget process) is **not**
implicated: that finding is specifically about a *second, mirroring*
`NSPersistentCloudKitContainer` — `1c` already ensures the widget's `PersistenceController`
never arms mirroring (`StoreLocation.Role.widget` → `armsCloudKitMirroring == false`).
`NotificationScheduler` itself needs only the already-open, non-mirroring
`PersistenceController` + a `NotificationSpecStore` + a `SnoozeRegistry` (a handful of
struct values, no additional Core Data stack) + `SystemUserNotificationCenter()` (a thin
protocol wrapper with no retained state). No incremental memory-budget risk.

**Verdict: give each of the three extension processes a real `NotificationScheduler`,
constructed at the same standardized site `1c` already built for their
`PersistenceController`.** No fallback/reconcile-on-next-foreground design needed — the
direct approach is unconditionally available.

### Design — "can't be forgotten again"

Per the wave brief: make the scheduler part of the construction bundle, not an optional
afterthought.

- **`Extensions/ShortcutsActions/IntentSupport.swift`** gains
  `static func makeTaskStore() async throws -> TaskStore`, which resolves
  `persistence` via the existing gated/cached path, constructs (or reuses a
  process-cached) `NotificationScheduler` hydrated the same way the two apps now are
  (see X10 below — reads `PreferencesStore` for the all-day default instead of
  hardcoding 9:00), assigns it to a freshly-constructed `TaskStore`, and returns the
  `TaskStore` pre-wired. Every existing `TaskStore(persistence: persistence)` call site
  in `Extensions/ShortcutsActions/` (`ToggleStatusIntent`, `CompleteTaskIntent`,
  `AddTaskIntent`, `TaskEntityQuery`) moves to `IntentSupport.makeTaskStore()` — this is
  the actual class-kill: a future intent added to this target gets a wired `TaskStore` by
  construction, the same way it gets `IntentSupport.makePersistence()`'s
  gating/caching by construction today.
- **`IntentSupport`** also exposes the constructed scheduler directly
  (`static func makeNotificationScheduler() async throws -> NotificationScheduler`) for
  `AddNudgeIntent`, which needs `scheduler.addNudge(...)` (persist + reconcile in one
  call, matching the app-level API) rather than `NotificationSpecStore.add` directly —
  today it bypasses scheduling entirely.
- **`CLIBridge.StatusHandler.run`** gains an optional
  `notificationScheduler: (any NotificationReconciling)? = nil` parameter (default `nil`
  preserves the CLI's own existing, deliberately-scheduler-free behavior — see
  `NudgeHandler`'s doc comment for why that's still correct for a genuinely short-lived,
  one-shot CLI process). After `tasks.transition(...)` it calls
  `await notificationScheduler?.reconcile(taskID: resolution.id)` when non-nil.
  `CompleteTaskIntent`/`ToggleStatusIntent` pass `try await IntentSupport.makeNotificationScheduler()`;
  the `lillist-cli` executable's own callers of `StatusHandler.run` are unchanged
  (omit the parameter, `nil` default, zero behavior change — verified by not touching
  `Packages/LillistCLI` at all in this plan).
- **`Extensions/LillistWidget/WidgetIntentSupport.swift`** gains the same
  `makeTaskStore()`/`makeNotificationScheduler()` shape (it's already documented as "a
  trimmed copy of ShortcutsActions' `IntentSupport`" since the widget target can't link
  that file). `AdvanceTaskStatusFromWidget` moves to `WidgetIntentSupport.makeTaskStore()`.
- **`Extensions/ShareExtension-iOS/ShareRootView.swift`** wires
  `taskStore.notificationScheduler` inline (it has no shared `IntentSupport`-style helper
  today, and this plan doesn't invent one for a single call site — matches the file's
  existing self-contained style). `ShareRootView` doesn't currently attach any reminder at
  share time, so this is forward-looking wiring (defense in depth per the "can't be
  forgotten again" framing), not a behavior change today.
- **Device fingerprint / transaction author:** each extension already stamps its own
  distinct `transactionAuthor` (`shareExtensionTransactionAuthor`, `appIntentsTransactionAuthor`,
  `widgetTransactionAuthor`) when constructing its `PersistenceController` — unchanged.
  `DeviceFingerprint.current()` is device-scoped, not process-scoped (already used
  identically by both apps' schedulers), so an extension-constructed scheduler installs/
  cancels requests under the exact same `"\(specID)#\(deviceFingerprint)"` identifiers the
  main app uses — a widget-issued cancel correctly removes the request the app most
  recently scheduled, and vice versa. `UNUserNotificationCenter`'s pending-request
  namespace is shared per containing app across all its extensions (same top-level bundle
  ID), not per-process — verified in the constraints section above, not assumed.

**CLI stays out of scope.** `NudgeHandler`'s existing doc comment documents a *prior,
deliberate* decision not to give the CLI a scheduler ("it would be wrong to wire one up
in a short-lived offline process... the running app reconciles it... next time it
launches"). `X8` names widget/Shortcuts/ShareExt specifically, not the CLI — a one-shot
terminal invocation is architecturally different from an interactive extension the OS
keeps alive slightly longer, where the user has an immediate expectation their action
took effect. Not revisited here.

---

## X9 — RemoteChangeReconciler's diff filter is too narrow

**Finding:** `RemoteChangeReconciler.affectedTaskIDs` only reacts to a foreign-authored
`NotificationSpec` change whose `changedProperties` contains `lastFiredAt`. Spec inserts
(a reminder added on another device never schedules here), spec deletes (a reminder
removed on another device keeps firing here), and task soft-deletes/restores (a task
trashed on another device keeps firing here; restored, it doesn't get its reminders back)
are all invisible to the diff.

### Investigation: what's actually recoverable from a persistent-history DELETE?

Checked empirically against this codebase's own established pattern, not assumed:
`LocalBackupCoordinator.processRemoteChange` (existing code, `Backup/LocalBackupCoordinator.swift:177-185`)
and `DiagnosticHistoryObserver.flatten` (`Diagnostics/DiagnosticHistoryObserver.swift:177-185`)
both already document the same finding — **`NSPersistentHistoryChange.tombstone` only
carries attribute values for attributes explicitly flagged
`preservesValueInHistoryOnDeletion` in the `.xcdatamodeld`, and *no* attribute on any
entity in this model has that flag set today** (confirmed by grepping
`LillistModel.xcdatamodel/contents` for `preservesValueInHistoryOnDeletion` — zero
matches). Relationships are **never** tombstoned regardless of any flag (an Apple/Core
Data hard limitation, not a configuration gap) — so even flagging `NotificationSpec.id`
for preservation would not recover the deleted spec's `task` link. Concretely: a foreign
`NotificationSpec` DELETE change gives us `changedObjectID` (an opaque, unresolvable-once-
deleted Core Data reference) and nothing else — no spec id, no task id.

**This means recovering "which task's reminder was deleted remotely" from history alone
is not possible without a data-model change** (flag `NotificationSpec.id` for
preservation — itself only a local Core Data history-tracking flag, not a new CloudKit-
synced field, but still an `.xcdatamodeld` edit, so still subject to the "no data-model
changes without messaging the orchestrator first" constraint out of caution). **Decided
directly, no council needed** — LocalBackupCoordinator's own established answer to
"can't identify a deleted row from history" is the right template here too: **set-
difference**, not tombstone recovery. `LocalBackupCoordinator` prunes package files by
diffing "what task files exist locally" against "what task ids currently exist in the
store." The equivalent here is diffing "what specIDs do our own currently-pending OS
requests reference" against "what `NotificationSpec` ids currently exist in the store" —
no tombstone, no model change, no orchestrator gate needed.

### Fix — widen `drainOnce()`'s diffing, three additions

All three stay inside `drainOnce()` (per `4a`'s closing-report instruction — not a
parallel code path), after the existing history fetch, before the watermark advance:

1. **Spec insert.** `SyntheticChange` gains a `changeType: NSPersistentHistoryChangeType`
   field (default `.update` in its memberwise init, so every existing test call site —
   all of which describe update scenarios — compiles and behaves unchanged). For
   `entityName == "NotificationSpec"`, foreign author, `changeType == .insert`: the row
   still exists (`ctx.existingObject(with:)` succeeds), so resolve `spec.task?.id` and add
   it to `affectedTaskIDs` — same shape as the existing `lastFiredAt`-update case, just a
   different `changeType` guard. **Scope note:** this widens to inserts and the existing
   `lastFiredAt` update — it deliberately does **not** widen to arbitrary other
   `NotificationSpec` property updates (e.g. a remote `snoozedUntil`/`offsetMinutes`
   edit) that `X9`'s finding text doesn't name; `NotificationSpecStore.update` today has
   exactly one production caller (`handleSnoozeAction`, same-device only — no UI path
   edits an existing spec's `offsetMinutes` in place, confirmed by grep, since reminders
   are create-or-delete, never edited in place). A remote snooze/offset-update reconcile
   gap is a real, narrower, *separate* residual — flagged below, not fixed here (avoids
   scope creep past the four named findings; matches this program's discipline).
2. **Task soft-delete/restore.** For `entityName == "LillistTask"`, foreign author,
   `changeType != .delete` (the task row itself is never hard-deleted by a soft-delete/
   restore — always an update), `changedProperties.contains("deletedAt")`: the row still
   exists, so resolve `task.id` directly (the change *is* the task) and add it to
   `affectedTaskIDs`. Covers both directions: trashed remotely → local pending should be
   cancelled (computed as `[]` for a deleted task); restored remotely → local pending
   should be recomputed (may now be non-empty again).
3. **Spec delete → orphan sweep, not per-id reconcile.** A new pure, synchronous static
   helper `RemoteChangeReconciler.hasForeignSpecDeletions(in:localAuthor:) -> Bool`
   (`entityName == "NotificationSpec"`, `changeType == .delete`, foreign author — no
   context access needed, matching the "no tombstone, no model change" finding above).
   When true, `drainOnce()` calls a new
   `NotificationScheduler.reconcileOrphanedPendingRequests()` (in addition to, not
   instead of, the taskID-keyed `onAffectedTasks` callback for whatever other changes were
   in the same batch): fetch this device's own pending requests once, batch-check which
   `specID`s in their `userInfo` still resolve to a live `NotificationSpec` row (new
   `NotificationSpecStore.existingIDs(among:) async -> Set<UUID>`, one `id IN %@` fetch —
   avoids N per-id round trips), and cancel whichever pending requests reference a spec
   that no longer exists. Self-healing for **any** stale pending request, not just the
   one that triggered the sweep — the same principle `H3`'s batched
   `cancelPending(forTaskIDs:)` already established for purge.
   `RemoteChangeReconciler`'s constructor gains an `onOrphanedSpecDeletions: @Sendable () async -> Void`
   closure (parallel shape to `onAffectedTasks`) so the diffing core stays
   `NotificationScheduler`-free, matching the existing dependency direction.

### macOS gets its own `RemoteChangeReconciler`

Per the ledger's wave-4a handoff note ("4b will likely give macOS its first
RemoteChangeReconciler instance too") and directly required by `X9` (macOS currently has
*no* remote-change-driven notification reconcile at all — an iPhone-added reminder never
schedules on the Mac until the Mac app is quit and relaunched, if ever). Wired in
`Apps/Lillist-macOS/Sources/AppEnvironment.swift`, mirroring the iOS construction exactly:
new `RemoteChangeReconciler(persistence:tokenStore:onAffectedTasks:onOrphanedSpecDeletions:)`
using `PersistentHistoryTokenStore(appGroupID: Self.appGroupID, key: PersistentHistoryTokenStore.defaultKey)`
— the key the macOS `HistoryWatermarks` construction (`3b`) already reserved specifically
for this ("macOS has no `RemoteChangeReconciler` of its own, but the `defaultKey`
watermark is still cleared for consistency/forward-compat" — that forward-compat is now
realized), `diagnosticLog` wired the same way iOS does, `.start()` + one bootstrap catch-up
`processPendingHistory()` call added to macOS `bootstrap()` at the same relative position
iOS uses (after `taskDuplicateReconciler`'s catch-up, before `TreeIntegrityChecker.repair`).
`localAuthor` is `persistence.transactionAuthor`, i.e. `PersistenceController.macAppTransactionAuthor`
— `4a`'s H6 fix is exactly what makes this safe to wire today without misclassifying the
Mac's own writes as foreign.

**Discovered, out-of-scope residual (flagged, not fixed here):** a remote
`NotificationSpec.snoozedUntil`/`.offsetMinutes` update (same-spec, in-place edit) is
still invisible to the diff — see point 1 above. No production code path creates this
scenario today (confirmed no UI edits an existing spec in place), so it's a latent, not
reachable, gap; filed as tracked debt for whichever future plan touches
`NotificationSpecStore.update`'s callers.

---

## X10 — all-day default hydration, reconcile-rewrite semantics, and timezone dedup

Three sub-parts.

### Part 1 — hydrate the default from `PreferencesStore` before any reconcile runs

**Finding:** both apps construct `NotificationScheduler`/`SnoozeRegistry` with a literal
`defaultAllDayHour: 9, defaultAllDayMinute: 0` — never reading the persisted
`PreferencesStore.Prefs.defaultAllDayHour`/`Minute` (the exact value the Settings/
Preferences surface already writes via `PreferencesStore.update` and reconciles via
`scheduler.updateDefaultAllDayTime`). On every cold launch where the user has ever
changed this setting away from the default, the in-memory scheduler starts wrong.

**Fix:** both apps' `bootstrap()` gains, immediately after `preferencesStore.normalizeSingletons()`
and strictly before `remoteChangeReconciler.processPendingHistory()`/`.start()` (so no
reconcile — remote-driven, purge-driven, restore-driven, or otherwise — runs against the
wrong in-memory default):

```swift
// X10: hydrate from the persisted preference BEFORE any reconcile pass runs —
// otherwise a catch-up reconcile below would recompute (and, pre-fix, incorrectly
// rewrite) all-day trigger times against the hardcoded 09:00 constructor default
// instead of the user's real preference.
if let prefs = try? await preferencesStore.read() {
    await notificationScheduler.updateDefaultAllDayTime(
        hour: Int(prefs.defaultAllDayHour),
        minute: Int(prefs.defaultAllDayMinute)
    )
}
```

This reuses `updateDefaultAllDayTime` exactly as Settings already does — no new
mechanism, one source of truth for "apply the default." Extension-constructed schedulers
(X8) get this hydration **at construction** instead (they have no `bootstrap()`
lifecycle — each invocation is fresh): `IntentSupport`/`WidgetIntentSupport`'s
`makeNotificationScheduler()` reads `PreferencesStore.read()` before constructing, so no
extension-issued scheduler is ever built with the hardcoded default at all.

### Part 2 — document `updateDefaultAllDayTime`'s rewrite semantics deliberately

**Finding text:** "reconcile actively rewrites correct pending triggers back to 09:00."
Traced to its root: this is a **direct symptom of Part 1's hydration gap**, not a
separate defect. Sequence without the fix: user sets default to 7:30 on Monday
(in-memory + persisted both become 7:30, existing triggers correctly rewritten); app
relaunches Tuesday with a **fresh** scheduler hardcoded back to 9:00; the first reconcile
for any reason (remote-change catch-up, purge, anything) recomputes the "desired" fire
time using the wrong in-memory 9:00, sees it differs from the correctly-pending 7:30
request, and — correctly, by `reconcile`'s own diffing logic — replaces it. The bug was
never in the diff/replace logic; it was that the compared-against default was wrong. Once
Part 1's hydration runs before any reconcile can fire, the in-memory default matches
persisted truth from the first reconcile onward, and this symptom cannot recur.

**What legitimately remains:** `updateDefaultAllDayTime` mid-session, on an explicit
Settings change, *intentionally* rewrites every all-day-anchored pending trigger to the
new default — this is correct, desired behavior (the user just told the system their
default reminder time changed), not a bug. Documented explicitly on the method (doc
comment addition, no behavior change) so a future contributor doesn't "fix" this
intentional rewrite into a no-op: **the only two callers of `updateDefaultAllDayTime` are
(a) bootstrap-time hydration to the value that produced the currently-pending triggers in
the first place — a no-op diff in the common case — and (b) an explicit user preference
change, where rewriting every dependent trigger is exactly the point.**

### Part 3 — the timezone dedup-defeat (council-decided)

**Decision (council, unanimous after deliberation):** see
`.council/x10-all-day-timezone-dedup-posture/DECISION.md` for the full audit trail.
Long-term fix is to anchor all-day fire times to a new synced "home time zone" field on
`AppPreferences` (not per-spec/task) — a genuine data-model change requiring
Development→Production CloudKit schema deploy, **out of scope for this plan** per the
binding "no data-model changes without messaging the orchestrator first" constraint.
Orchestrator flagged (message sent to `team-lead` before this plan doc was committed);
not blocking — this plan proceeds with the council's own required interim discipline:

1. **Design doc note.** `docs/plans/2026-05-12-lillist-design.md` Section 4 ("Cross-device
   de-duplication") gains a line documenting that all-day dedup is currently correct only
   for same-time-zone devices — cross-timezone devices legitimately fire independently —
   as a **tracked, known limitation** (linking `LIL-83`), not a redefinition of the
   existing "acceptable race window: a few seconds" promise.
2. **TODO markers** at both `timeZone: .current` `NotificationScheduler(...)` construction
   sites (`Apps/Lillist-iOS/Sources/App/AppEnvironment.swift`,
   `Apps/Lillist-macOS/Sources/AppEnvironment.swift`), citing `LIL-83`.
3. **KNOWN LIMITATION regression test** — proves same-timezone devices dedup correctly
   (already true; guards against regressing the working case while touching this file)
   and differing-timezone devices legitimately diverge (the documented gap; named and
   commented so this specific assertion is deleted, not "fixed forward," the moment
   `LIL-83` ships).
4. `LIL-83` filed (done — see *Storyhook* below), naming the flaw, the interim patch's
   limits, and the redesign trigger, per CLAUDE.md's deliberate-tech-debt-logging rule.

**Option (b) (widen the dedup tolerance window) is explicitly rejected**, not merely
unchosen — proven mathematically unfixable by the *existing*
`NotificationSchedulerCrossDeviceDedupTests.deadlineChangeAfterFireReschedules` test
(asserts a legitimate re-fire after an exact 86,400s/24h forward reschedule), which
pins the window below 24h while realistic/worst-case timezone deltas need ~24h+ to
suppress the duplicate — an unresolvable overlap. No implementation attempted for this
option.

---

## Verification plan

Per the ledger's binding verification protocol:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/LillistCore --parallel --num-workers 2 > /tmp/suite.log 2>&1; echo EXIT:$?
grep -E "Test Suite .* failed|Note: Some test targets reported failures" /tmp/suite.log
```

Run twice (this plan touches shared construction sites in both `AppEnvironment.swift`s
and adds a new macOS `RemoteChangeReconciler` instance — matches the ledger's "shared
test fixture state" re-run trigger). Plus unsigned `xcodebuild` builds for both apps
(the widget, Shortcuts, and Share Extension targets build within their respective app
schemes, so a green app build covers them).

**Real-device manual checklist additions** (added to the ledger's checklist): complete a
task from the Home Screen widget on a physical device and confirm its OS reminder
disappears; add a nudge via Shortcuts and confirm it actually fires; delete a reminder on
one device and confirm a second device (same account, same time zone) drops its matching
pending request within a launch/foreground cycle.

## Commit plan (two hats, one red→green cycle per commit)

1. `docs: plan-4b notification-truthfulness design + council decision` (this file +
   council artifacts, already on disk).
2. `fix(core): H2 — reconcile notifications for the full softDelete/restore subtree` —
   `Closes LIL-20`.
3. `feat(core): X8 — extension processes construct a wired notification scheduler` (may
   split into iOS-Shortcuts / widget / share-extension sub-commits if the diff is large
   enough to want independent red→green checkpoints) — `Closes LIL-39`.
4. `fix(core): X9 — widen RemoteChangeReconciler to spec insert/delete + task soft-delete/restore`
   — `Closes LIL-40`.
5. `feat(macos): X9 — give macOS its own RemoteChangeReconciler` (separate from #4 — new
   wiring in a different app target, distinct from the core diffing widen).
6. `fix(core): X10 part 1/2 — hydrate all-day default from prefs at bootstrap, document rewrite semantics`
   — `Closes LIL-41`.
7. `docs+test: X10 part 3 — document timezone dedup limitation, land KNOWN LIMITATION regression test`
   (docs-plus-test, not a behavior change — own commit per two-hats).
8. `chore(stories): plan-4b done-move`.
