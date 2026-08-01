# APPROVAL — ios-widget-shows-redacted-content

**Decision: `fix`**

Granted by the user (Mikey), 2026-07-31, in response to the `DIAGNOSIS.md` summary and an explicit
statement of this investigation's two limits (below). Instruction: *"implement the fix"*.

## Scope authorized

- **C1** — short-circuit `SmartFilterEntityQuery.entities(for:)` when the requested identifiers are
  fully satisfiable without a store read (the `unfilteredID` sentinel).
- **C2** — bound every store-open the widget process awaits, with a documented fallback.
- **C3** — invert `allFilters()`'s ordering so the cheap index read leads and the live store is the
  enhancement, not the prerequisite.
- **C4** — `WidgetSnapshotBuilder.performRegenerate`'s fail-unsafe `(try? …) ?? []` sentinel write,
  plus the protocol seam that makes it testable. **Separate commits** (two hats).

## Limits the user accepted when approving

1. **The iOS repro gate is NOT MET.** No automated test reproduces the iOS defect. The one existing
   test (`WidgetExtensionRegistrationReproTests`) reproduces **LIL-92 (macOS)**. The fix therefore
   ships with *new* tests written red-first against the seam C2 introduces, but the end-to-end
   user-visible failure remains unreproduced.
2. **The hang is inferred, not observed.** Confidence is HIGH on mechanism shape, UNCONFIRMED at
   runtime. The owed confirmation — Console.app on the device during a widget reload, looking for
   `ApplicationExtension record not found` or an extension timeout — has not been performed, and
   distinguishes "our hang" from the documented Apple `AppIntentTimelineProvider` bug
   (FB13880020 / FB18180368 / Apple Forums 814463).

The remediation is correct under either attribution: it removes the dependency of intent resolution
on an unbounded store open, which is both the fix for a self-inflicted hang and the hardening that
survives the platform bug.

## Constraints in force

- Two hats: behavior fix commits carry no refactoring; refactors are separate commits.
- Every commit builds and passes tests (bisectable history).
- Branch → HTTPS push → PR → merge commit. No force-push. No version bump, no deploy.
- Device verification is the user's; `/deployit` cannot confirm this from here.
