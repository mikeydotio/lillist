# Hypothesis Report

## 5 Whys
1. **Why a full-screen "Could not load tasks"?** `TasksView.applyDrop` catches any
   reorder/reparent throw into `loadError`, which drives the `TasksScreen` "Could not load
   tasks" surface. A **write** failure mislabeled as a **load** failure. (R2)
2. **Why did reorder throw `anchors out of order`?** The `anchorsAreOutOfOrder` guard saw the
   two targeted neighbors with `after.position >= before.position`. It reads pre-existing
   positions and rolls back — so the drag didn't create the bad pair; it **pre-existed**.
3. **Why did two bottom siblings already tie/invert?** `nextPosition = max(position) + 1.0` is a
   non-atomic read-then-write. Two appends reading the same `max` both write `max+1.0` → equal
   tail pair. Single-device bisection math is proven sound, so the tie came from an integer-step
   **append**, not underflow.
4. **Why can two appends read the same `max` without serializing?** `nextPosition` is atomic only
   within one `NSManagedObjectContext` queue. The Share Extension and App Intents extension are
   **separate XPC processes** with their own contexts over the same App-Group store; CloudKit
   imports replay foreign positions. None honor the single-context discipline.
5. **Why does ordering rely on a non-atomic, uncoordinated allocator (ROOT)?** Fractional ordering
   was designed for single-context/single-device serialization, but the product ships **multiple
   concurrent writers it cannot serialize** (two XPC extensions on a shared store + last-writer-wins
   CloudKit sync with no position normalization), with **no `(parent,position)` uniqueness
   constraint** and **no load-time normalization**. The "strictly increasing siblings" invariant is
   *assumed* by the guard but *enforced by nobody at write time*.

## Hypotheses (ranked)
| ID | Statement | Confidence | Verdict (Phase 4) |
|----|-----------|-----------|--------------------|
| **H-A** | Concurrent **cross-process** appends (Share/App-Intents XPC) each read same `max`, write `max+1.0` → equal tail pair | HIGH | **DEEPER_CAUSE_FOUND** |
| **H-B** | CloudKit per-attribute LWW merge yields equal/inverted siblings across devices | MEDIUM | **DEEPER_CAUSE_FOUND** (merge policy is a *red herring*; reduces to H-A's root) |
| **R1** | Guard runs *before* the `recompactSiblings` self-heal → the repair is unreachable on the path it could fix | HIGH | **SURVIVES** (resilience, not origin) |
| **R2** | Reorder write failure surfaced as "Could not load tasks" via `loadError` | HIGH | (structural fact) |
| **R3** | No load-time/bootstrap normalization → tie persists silently until a drag hits it | HIGH | (structural fact) |
| **H-E** | Single-device integer-step end-insert collides with an existing non-neighbor sibling | LOW | secondary degeneracy |
| **H-D** | Compactor/recompaction defect writes degenerate positions | LOW | **REFUTED** (compactor correct; just unreachable) |
| **H-C** | Float underflow collapses a midpoint while `needsCompaction` is false | LOW | **REFUTED** (2M-pair search, 0 violations) |

## Convergence
H-A and H-B are **the same root cause** (non-atomic, uncoordinated `nextPosition` across writers);
H-B's distinctive "merge policy synthesizes the tie" claim is false — the trump policy never fires
for two distinct INSERTs and can only *transport* a tie minted by the same arithmetic on another
device. H-A reaches the root with the strictly weaker precondition (a second OS process on **one**
device, no iCloud required), so it is the most probable concrete trigger.

## Recommended Verification Priority
H-A first (top-ranked, on-device, testable via the existing two-context race-test pattern), then
confirm R1/R2/R3 as co-occurring resilience defects that turn a recoverable tie into a bricked list.
