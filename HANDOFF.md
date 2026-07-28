# HANDOFF — Data & Sync Hardening, Wave 1b → Wave 1c

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories), Wave 1 plan `1a` (`trash-tree-integrity`),
and Wave 1 plan `1b` (`purge-cloudkit-retirement`) all **COMPLETE**. Plans
`1c`-`1d` and Waves 2-6 not started.

## What landed this wave (plan `1b`)

All 3 findings closed (`C4`/`X4` merged, `H3`, `X14` / stories `LIL-10`
`LIL-21` `LIL-63`). Retired `NSBatchDeleteRequest` from both trash-purge
paths (`TaskStore.batchPurge`, `AutoPurgeJob.run`) in favor of a new shared
`TrashPurger` that deletes via chunked managed-object-context deletes —
`NSBatchDeleteRequest` bypasses `NSPersistentCloudKitContainer`'s export
tracking, so a purged task's `CKRecord` could resurrect from the zone.
Added delete-time predicate revalidation (a task restored, or re-trashed
past a retention cutoff, mid-purge must survive) and OS-notification
cancellation for `hardDelete`/`purgeAll`/`AutoPurgeJob` (a new
`NotificationReconciling.cancelPending(forTaskIDs:)` method, since the
existing `reconcile(taskID:)` silently no-ops once the row is gone). Full
detail — per-finding fix design, `TrashPurger`'s shape, the `CascadeReaper`
fate verdict, chunk-size rationale — is in:

- Plan doc: `docs/superpowers/plans/2026-07-28-plan-1b-purge-cloudkit-retirement.md`
- Ledger's **Wave 1b closing report** section (in the index doc below) —
  per-finding commit/test table and exactly what `TaskStore.swift`/
  `AutoPurgeJob.swift`/`NotificationReconciling.swift` now look like for
  `4b`/`5a` (the `TaskStore.swift` serial chain's next links) to build on.

Commit range: `bcfa04ac..33170218` (4 commits: 1 docs, 2 fix, 2
`chore(stories)`). Verification: full `LillistCore` suite green (1144
tests, 219 suites, up from `1a`'s 1134/216 baseline) after every fix
commit; both apps built successfully with unsigned `xcodebuild`.

One correction worth flagging: the wave-1b brief cited wrong story IDs for
`H3`/`X14` (`LIL-23`/`LIL-48`, which actually belong to `H5`/`M4` under
`plan-5a`) — flagged to `team-lead`, and the correct IDs (`LIL-21`/`LIL-63`,
matching the ledger's own cross-reference table) were used for every `1b`
commit.

## Next action

**Start Wave 1, plan `1c` (`store-location-unification`)** — findings
`X1 X2 X15` (+ the iOS silent `defaultOnDisk` fallback detail folded into
`X1`/`X2`'s story bodies, no separate ID). This plan does **not** sit on
the `TaskStore.swift` serial chain (that chain's next link is `4b`) — its
hotspots are `AppEnvironment.swift` (both iOS and macOS — distinct
regions, serialize per-platform per the ledger's shared-file-chain note)
and the store-location resolvers (`StoreConfiguration`, `StoreLocator`,
`appGroupOnDisk`/`defaultOnDisk`). Re-read those before editing —
`AppEnvironment.swift` already picked up one small `1b` change each
(iOS/macOS): `autoPurgeJob.notificationScheduler = scheduler`, right after
the existing `taskStore.notificationScheduler` assignment.

`1c`'s core problem (`X1`): the macOS app never joined the App Group — its
widget resolves the App Group path, finds nothing, and opens/creates a
**second, empty** `Lillist.sqlite`, importing the *entire account* into it
in iCloud mode. `X2`: the `lillist` CLI builds a *third*, different path.
Class-killer verdict already recorded in the ledger's *Class-killer
verdicts* table: adopt a canonical `StoreLocation` resolver + a
multi-process pin test (no test currently opens two `PersistenceController`s
against one store file — that's why `X1`/`X2`/`X5`/`X7`/`X15`/`X20` were
invisible to CI).

Read the ledger's *Resume protocol* section first (confirm worktree/branch,
re-read the review + ledger, check story state, verify Wave 1b's claimed-
green state, execute, update the ledger on completion).

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
