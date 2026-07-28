# HANDOFF — Data & Sync Hardening, Wave 0 → Wave 1

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories, no code) **COMPLETE**. Waves 1-6 not started.

## What landed this wave

- `docs/reviews/2026-07-28-data-sync-review.md` — the full 70-finding review
  (25 stores/persistence, 26 sync machinery, 20 cross-process; `C4`/`X4`
  merged as one independently-corroborated defect). Read this first for
  *why* the program exists.
- `docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md` — the
  **living ledger**. Read this second — it has the wave/plan table, shared-
  file serial chains, resume protocol, story-ID cross-reference table, and
  Mikey's manual-verification checklist. **This is the source of truth for
  "what's next."**
- All 70 findings filed as storyhook stories `LIL-7` through `LIL-76`.
- One council-vote decision recorded (`C4`/`X4` story granularity — merged,
  not split; audit trail at
  `.council/c4-x4-merged-or-two-linked-stories/DECISION.md`).

## A blocker worth knowing about

Storyhook's `story new` initially failed unconditionally in this worktree
(`.storyhook/open/` — where the CLI writes active stories — wasn't
git-tracked, since git doesn't commit empty directories and this project's
prior stories were all archived). It was resolved mid-wave; the fix is
committed. If a *future* fresh worktree of this repo somehow hits the same
symptom, the ledger's *Current status* section has the full root-cause
writeup and fix.

## Next action

**Start Wave 1, plan `1a` (`trash-tree-integrity`)** — closes `C1 C2 C3 M1
M2 H4 H7 M5` (stories `LIL-7`, `LIL-8`, `LIL-9`, `LIL-45`, `LIL-46`,
`LIL-22`, `LIL-25`, `LIL-49`). It has no upstream dependency and owns the
first link in the `TaskStore.swift` serial chain (four plans deep — `1a` →
`1b` → `4b` → `5a`). Two binding product decisions apply here: `C2`
(restoring a child whose parent is still trashed promotes it to root) and
the `TreeIntegrityChecker` class-killer (adopt, per the ledger's verdicts
table).

Read the ledger's *Resume protocol* section for the full pre-flight
(confirm worktree/branch, re-read the review + ledger, check story state,
verify the prior wave's test-green claim, execute, update the ledger on
completion).

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
