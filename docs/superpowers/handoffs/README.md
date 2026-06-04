# Foundation Hardening — Wave Handoffs

Each wave of the Foundation Hardening program
([index](../plans/2026-05-29-foundation-hardening-index.md)) is executed by a
*different* executor working in a vacuum. These files are the connective tissue:
**every executor reads the prior wave's handoff before starting and writes its
own (`wave-N.md`) on completion.**

Waves 1–3 are **backfilled** here from the index's status entries (they merged
before this protocol existed). Waves 4–7 are written by their executors as they
land.

## Template

```markdown
# Wave N handoff
From: Wave N executor   To: Wave N+1 executor   Date: <abs date>

## What landed
- <plan>: commits <shas>; <N> LillistCore tests green (+ iOS scheme if app-touching). Closed: <findings>.

## Shared files I moved (anchor by structure — line numbers are as-of-landing)
- <file>: <method/section> now ~<line>; <what changed>

## Assumptions I invalidated for later waves
- <e.g. runMigration gained a reentrancy guard at its first statement>

## Residuals I opened / closed
- <#refs into the index "Known residuals" list>

## Pre-flight the next executor should run
- git log --oneline main | head -20   (confirm my commits present)
- <re-Read commands / anchor greps the next wave needs>
```

## Standing rules (apply to every wave)

- Anchor by code **structure**, not line number — each wave shifts the shared
  hotspot files (`MigrationCoordinator`, `TaskStore`, `SmartFilterStore`,
  `PersistenceController`, `LillistCommands`, both `AppEnvironment`s).
- Run the full `swift test --package-path Packages/LillistCore` (+ `…/LillistUI`)
  after each plan; the iOS scheme after any app/extension/model change; the
  host-gated swap + app-hosted tests on a signed simulator.
- A single intermittent SIGSEGV/timing flake under parallel tests is residual
  #11 (test-harness CPU contention, not a product bug) — re-run before treating
  it as real. ci-and-build-posture (Wave 7) owns the permanent fix.
