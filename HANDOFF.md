# HANDOFF — Data & Sync Hardening, Wave 1a → Wave 1b

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories) and Wave 1 plan `1a` (`trash-tree-integrity`)
**COMPLETE**. Plans `1b`-`1d` and Waves 2-6 not started.

## What landed this wave (plan `1a`)

All 8 findings closed (`C1 C2 C3 H4 H7 M1 M2 M5` / stories `LIL-7 LIL-8
LIL-9 LIL-22 LIL-25 LIL-45 LIL-46 LIL-49`), plus the `TreeIntegrityChecker`
class-killer, wired into both apps' launch bootstrap. Full detail — per-
finding fix design, state machine, `TreeIntegrityChecker` UML, the H7
council decision — is in:

- Plan doc: `docs/superpowers/plans/2026-07-28-plan-1a-trash-tree-integrity.md`
- Ledger's **Wave 1a closing report** section (in the index doc below) —
  per-finding commit/test table, class-kill demo notes, and exactly what
  `TaskStore.swift`/`CascadeReaper.swift`/`AutoPurgeJob.swift` now look like
  for `1b` to build on.

Commit range: `8e13b98f..56100933` (13 commits). Verification: full
`LillistCore` suite green (1134 tests, 216 suites) after every fix commit;
both apps built successfully with unsigned `xcodebuild` (no
`Signing.local.xcconfig` in this worktree).

One find worth flagging explicitly: the `H7` regression test for
`RecurrenceSpawner.deepCopy` reproduced a **real SIGSEGV** (stack overflow),
not merely a hang — the fix needed a hard node-count cap in addition to the
visited-objectID guard, because the function's own newly-created copies get
wired back into the graph it's walking. See the closing report for the
mechanism.

## Next action

**Start Wave 1, plan `1b` (`purge-cloudkit-retirement`)** — findings `C4`/`X4`
(merged, `LIL-10`), `H3` (`LIL-21`), `X14` (`LIL-63`). It's next in the
`TaskStore.swift` serial chain (`1a` → `1b` → `4b` → `5a`) — **re-read
`TaskStore.swift`, `CascadeReaper.swift`, and `AutoPurgeJob.swift` before
editing them**; `1a` changed all three (new `CascadeReaper.planPurge`,
`TaskTreeRepair.promoteToRoot`, `assertParentNotTrashed`, two-arity
`applySoftDelete`/`clearSoftDelete`). The ledger's closing report for `1a`
spells out exactly what changed and what `1b` must preserve (promote-then-
delete ordering in the purge path, in particular).

`1b`'s core question (`C4`/`X4`): batch-delete purge may not export
deletions to CloudKit at all (`NSBatchDeleteRequest` bypasses the object
graph `NSPersistentCloudKitContainer` normally tracks). Device verification
is opportunistic for Mikey, **not** a gate — the fix proceeds regardless,
per the documented Apple limitation with mirrored-context deletes (see the
review doc and ledger's *Execution model* section).

Read the ledger's *Resume protocol* section first (confirm worktree/branch,
re-read the review + ledger, check story state, verify Wave 1a's claimed-
green state, execute, update the ledger on completion).

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
