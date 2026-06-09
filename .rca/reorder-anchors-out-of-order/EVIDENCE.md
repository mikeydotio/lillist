# Evidence Report

Gathered by 4 parallel read-only agents (git archaeology, concurrency/persistence,
test-coverage, float-math). All claims verified against code by the orchestrator.

## Git History Findings
- The `anchorsAreOutOfOrder` guard in `TaskStore.reorder` is **2 days old**: helper landed
  `3ecd71d` (2026-06-04 09:25:37), wired in by `88a923e` (09:26:26). Symptom occurred
  2026-06-06 (build 38). The guard **surfaces** pre-existing bad data; before it, reorder
  silently bisected a degenerate gap. Commit body: "matches the guard SmartFilterStore
  already had" — a defensive precondition, **not** a fix for a logged corruption incident.
- **Guard-before-heal is structural, by commit sequencing.** The `recompactSiblings` self-heal
  landed ~90s *after* the guard (`e18b6b3` 09:27:52) and sits *below* it in source
  (TaskStore.swift:316 throw vs 338-343 heal). Same in `SmartFilterStore` (267 vs 278-283).
- `nextPosition = max(position) + 1.0` has been **non-atomic since the first commit**
  (`57d6f52`, 2026-05-13); never a unique/atomic allocator. `create` (138), `reparent` (288)
  both route through it.
- Commit `17ba9e3` (TagStore race test) **documents the project's own atomicity model**:
  no-duplicate holds *only* because every in-app caller shares the single main-queue
  `viewContext`; two independent contexts interleaved **do** produce duplicates.
- CloudKit merge policy is `mergeByPropertyObjectTrump` (last-writer-wins per attribute) on
  both contexts (PersistenceController.swift:61,116); documented YAGNI in
  engineering-notes.md:1956-1962. `position` is `optional Double default 0`, **no uniqueness
  constraint** (model contents:12,32,83), and CloudKit can't mirror constraints anyway (notes:2054).

## Architecture / Concurrency Findings
- Store is `NSPersistentCloudKitContainer`; history tracking + remote-change notifications on.
- **Same-process appends cannot tie**: `create()` runs `nextPosition` + `save()` inside one
  `context.perform` on the single shared `viewContext` (TaskStore.swift:7,122-141) → serialized.
- **Cross-process appends genuinely race.** The **Share Extension** (`com.apple.share-services`)
  and **App Intents extension** (`com.apple.appintents-extension`) are separate XPC processes
  (project.yml:74-75,98-99) that each build their **own** `PersistenceController` over the same
  App-Group `Lillist.sqlite` (StoreConfiguration.swift:73-82; ShareRootView.swift:82-83;
  IntentSupport/AddTaskIntent.swift:25). Two appends read the same `max` → both write `max+1.0`
  → **equal-position pair at the tail** (= bottom of list).
- No de-dup/normalization of `position` on CloudKit import (`RemoteChangeReconciler` only reacts
  to `NotificationSpec.lastFiredAt`, :152-155). A tie persists indefinitely.
- **UI vs store tie-break disagree.** Personalized sort tie-breaks on `id.uuidString`
  (TaskTree.swift:86-89); store fetch tie-breaks on `createdAt` (TaskStore.swift:263-266). For a
  tied pair the visible neighbor order can disagree with persisted order, so a normal drag lands
  on the degenerate gap. `DragController.resolveBetweenBelow` on a tied tail pair →
  `reorder(after=2nd-last, before=bottom)` with `after.position == before.position` → guard throws.

## Float-Math Findings (H-C)
- **Arithmetically refuted.** Midpoint collapse onto a neighbor requires gap ≤ 1·ulp(a);
  `gapIsTooSmall` fires at gap ≤ 4·ulp(a) — a 4× conservative margin. Smallest gap where
  `needsCompaction` is false is 5·ulp(a), whose midpoint sits 2 ulp above a / 3 ulp below b.
- A randomized search of **2,000,000 (a,b) pairs** at 1–20 ulp gaps across bases 1.0…1e6 found
  **zero** cases where `gapIsTooSmall` is false yet `(a+b)/2` is not strictly between a and b.
- The only same-device arithmetic paths that *can* mint a duplicate are the **integer-step
  end-inserts** (`a+1.0`/`b-1.0`) and `nextPosition` (`max+1.0`), which are not gap-bounded and
  unchecked against non-neighbor siblings (→ H-E, low probability).

## Test Coverage Gaps
NOT-COVERED: (a) reorder into an already-equal pair; (b) reorder into a persisted inversion;
(c) concurrent/cross-process create producing equal tail positions; (d) CloudKit merge producing
degenerate positions; (f) proof the guard short-circuits the self-heal; (h) resolver picking a
degenerate persisted gap. COVERED-as-tolerant: (g) load over degenerate positions (structurally
cannot throw "anchors out of order"). NOT a real defect: (e) underflow-without-flag (math refuted).
The exact failure chain (c → tie → f → R2) is **entirely untested**.

## Key Facts (ranked)
1. The bad pair **pre-existed** the drag (`reorder` rolls back on throw; TaskStore.swift:352-355).
2. The producer is **non-atomic `nextPosition` across uncoordinated writers**, the Share/App-Intents
   XPC extensions being the most likely on-device trigger; CloudKit is the cross-device variant.
3. Float underflow and a compactor bug are both **ruled out**.
4. Three resilience defects compound it: R1 guard-before-heal, R2 write-error-as-load-error,
   R3 no load-time normalization.
