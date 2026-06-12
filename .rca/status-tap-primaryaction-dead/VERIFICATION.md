# Root Cause Verification

## Verified Root Cause
The row-wide drag-reorder gesture — `LongPressGesture.sequenced(before:
DragGesture(minimumDistance: 0))` attached via `.gesture` over the ENTIRE row
(d909e75, build 26) — consumes quick taps on the embedded
`Menu(primaryAction:)` status control, so `primaryAction` never fires.

## Causal Chain (Verified)
1. Tap lands on the status control — verified: tap does not navigate (control
   claims the touch) and calibration long-press reaches the same control.
2. `primaryAction`/onClick never runs — verified: StatusCycler has no fixed
   point and the identical store path works via the menu, so a firing onClick
   would always visibly change status.
3. The row drag gesture is the consumer — verified by variant matrix:
   gesture removed → tap works (V2); NavigationLink removed with gesture
   kept → still dead (V1). Single-factor confirmation.
4. Shipped in build 26 — verified by deploy-boundary git archaeology; no
   later commit touched the path.

## Heuristic Checks
| Heuristic | Pass/Fail | Notes |
|-----------|-----------|-------|
| Structural fix, not defensive check | PASS | gesture scoped away from controls; no arbitration tuning |
| Prevents multiple symptom manifestations | PASS | also revives the disclosure-chevron taps on parent rows |
| Violates no existing invariants | PASS | drag overlay geometry unchanged (`reportRowGeometry` stays row-level) |
| Doesn't require careful ordering | PASS | composition, not sequencing |
| Generalizable / teaches about architecture | PASS | "drag gestures never cover interactive controls" rule |
| Fix at origin of bad state | PASS | the gesture attachment is the origin |

## Challenger's Assessment
- "Title taps work on device, so why doesn't the gesture kill those too?"
  — Cell selection (UIKit) and embedded-control taps have different
  relationships to SwiftUI's row-level recognizers; the sim (where title taps
  fail even gesture-free) confirms they are independent mechanisms.
- "Could it be the deprecated menuStyle?" — V2 revived the tap with the
  menuStyle untouched; refuted as the cause.

## Confidence Level: HIGH
Single-variable falsification on the real app, both directions (necessary:
V0/V1 dead with gesture; sufficient: V2 alive without).

## Alternative Explanations Eliminated
| Hypothesis | Why Eliminated |
|-----------|----------------|
| H1 NavigationLink suppression | V1: link removed, tap still dead |
| H3 deprecated borderlessButton menuStyle | V2: tap revived with style untouched |
| Stale-record no-op transitions | menu path proves records fresh; StatusCycler has no fixed point |
| Store/write stall | list reads + menu writes + all other mutations healthy |
| Device iOS update | break predates the update (user-confirmed) |
