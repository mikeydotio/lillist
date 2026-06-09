# Root Cause Verification

## Verified Root Cause
**An unenforced sibling-position ordering invariant.** New rows are positioned by
`nextPosition = max(position) + 1.0` (TaskStore.swift:685-696) — a non-atomic
read-max-then-write that is serialized **only within a single `NSManagedObjectContext`**.
The product ships multiple writers that share the App-Group store but **not** that context —
the Share Extension and App Intents extension (separate XPC processes), plus CloudKit-mirrored
creates from other devices — so two concurrent appends both read the same `max` and both write
`max + 1.0`, minting **two equal-position siblings at the tail of the list**. With no
`(parent, position)` uniqueness constraint (and none possible under CloudKit) and no load-time
normalization, the tie persists silently until a drag resolves into that exact gap; the reorder
`anchorsAreOutOfOrder` guard then rejects it.

## Causal Chain (Verified)
1. **Symptom:** full-screen "Could not load tasks" + `validationFailed([… "anchors out of order"])`
   — verified by the screenshot string + `TasksScreen` rendering `loadError`.
2. **Surfacing (R2):** `TasksView.applyDrop` catch sets `loadError = "\(error)"` (TasksView.swift:285);
   load itself never validates anchors and would have succeeded.
3. **Throw:** `reorder` guard `anchorsAreOutOfOrder(after, before)` returns true for `after >= before`
   (FractionalPosition.swift:36-39; TaskStore.swift:316-323), then rolls back (352-355) → bad pair pre-existed.
4. **Unreachable repair (R1):** the guard (line 316) precedes `needsCompaction → recompactSiblings`
   (338-343); the heal that would re-space the tie never runs on the throwing path.
5. **Origin:** two siblings already tied at the tail via non-atomic `nextPosition = max+1.0`
   (TaskStore.swift:685-696,138) written by **uncoordinated concurrent writers**.
6. **Root:** no atomic/coordinated/constrained enforcement of the strictly-increasing-siblings
   invariant across the system's real (multi-process, multi-device) writer set; no load-time normalize (R3).

## Heuristic Checks
| Heuristic | Pass/Fail | Notes |
|-----------|-----------|-------|
| Structural fix, not defensive check | PASS | Root is a missing invariant-enforcement layer, not a one-off |
| Prevents multiple symptom manifestations | PASS | Same defect underlies SmartFilter reorder + any future writer |
| Violates no existing invariants | PASS | Strengthens the ordering invariant CloudKit can't express as a constraint |
| Doesn't require careful ordering | PARTIAL | Fix must keep rejecting genuinely-inverted *requests* while healing degenerate *data* |
| Generalizable / teaches architecture | PASS | "single-context atomicity ≠ cross-process atomicity" (cf. commit 17ba9e3) |
| Fix at origin of bad state, not encounter point | PASS | Targets `nextPosition` + load-time normalize, not just the reorder guard |

## Challenger's Assessment
- **H-A → DEEPER_CAUSE_FOUND (conf. MEDIUM):** every code-level refutation failed. Confirmed the
  XPC extensions are separate processes on the shared store; confirmed no uniqueness/version
  constraint and that `mergeByPropertyObjectTrump` never fires on two distinct INSERTs; confirmed
  the existing `TagStoreFindOrCreateRaceTests` proves the identical read-then-write window persists
  duplicates. MEDIUM (not HIGH) only because **which** writer minted the once-seen tie can't be
  attributed post-hoc without persistent-history transaction authors (data disposable).
- **H-B → DEEPER_CAUSE_FOUND:** the CloudKit **merge policy is a red herring** — it transports a tie
  another device minted via the same `nextPosition` arithmetic; it does not synthesize one. Reduces to H-A's root.
- **R1 → SURVIVES (conf. HIGH):** verified the heal has only two call sites, both below their guards;
  no load/background/migration normalization exists. **Important fix nuance:** the guard does double
  duty — it must keep rejecting a genuinely **inverted caller request** (args swapped; covered by
  `TaskStoreOrderingTests` 58-70) while **healing degenerate data**. So the fix is "normalize the data,
  then **re-evaluate** the guard," not "remove the guard." (And recompaction must respace in the order
  the UI presents, since UI tie-break is `id` while the store's is `createdAt`.)

## Architectural Pattern Match
**Leaky concurrency abstraction** — an allocator whose atomicity guarantee (single serial context)
is silently broken by the real deployment topology (multiple OS processes + CloudKit). Compounded by
**fail-closed validation without a recovery path** (guard before heal; write-error as load-error).

## Confidence Level: HIGH (mechanism) / MEDIUM (which writer triggered the once-seen instance)
The *mechanism* (non-atomic uncoordinated `nextPosition` → equal tail pair → guard-before-heal →
load-error surface) is proven in source and arithmetic. The *specific* triggering writer for this
one occurrence is unattributable post-hoc — which is itself the motivation for the diagnostic
logging feature now being built (create/reorder events with process/author + indices/anchors).

## Alternative Explanations Eliminated
| Hypothesis | Why Eliminated |
|-----------|----------------|
| H-C (float underflow) | `gapIsTooSmall` (≤4 ulp) fires 4× before midpoint collapse (≤1 ulp); 2M-pair search found 0 violations |
| H-D (compactor bug) | `PositionCompactor` assigns distinct 1..n by sorted index — correct; only unreachable (that's R1) |
| H-B as distinct cause | Merge policy never fires for two INSERTs; CloudKit only transports an upstream tie |

## Remediation Direction (for Phase 5)
1. **Origin:** make tail/position allocation robust to concurrent & cross-process writers — detect/repair
   duplicate positions on write, since a Core Data uniqueness constraint is impossible under CloudKit.
2. **Self-heal (R1):** in `reorder`, recompact-then-re-check when the *data* is degenerate (tie/inversion
   among the actual neighbors), respacing in presentation order, while still rejecting a genuinely
   inverted *request*. Mirror in `SmartFilterStore`.
3. **Load-time normalize (R3):** a bootstrap/`evaluate`-time pass that repairs adjacent degenerate
   anchors so a pre-existing tie heals instead of lurking.
4. **Surfacing (R2):** give reorder failures a transient, non-blocking surface distinct from
   "Could not load tasks," and never dump raw `validationFailed(...)` to the user.
5. **Tests:** the entire chain is untested — add store-level tests for (c) concurrent/cross-context
   create tie, (a)/(b) reorder into equal/inverted persisted pairs (heal, don't brick), (f) guard-vs-heal
   ordering, and load-time normalization; reuse the `TagStoreFindOrCreateRaceTests` two-context pattern.
