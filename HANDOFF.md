# HANDOFF — Data & Sync Hardening, Wave 1c → Wave 1d

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories) and Wave 1 plans `1a`
(`trash-tree-integrity`), `1b` (`purge-cloudkit-retirement`), and `1c`
(`store-location-unification`) all **COMPLETE**. Plan `1d` and Waves 2-6
not started.

## What landed this wave (plan `1c`)

All 3 findings closed (`X1`, `X2`, `X15` / stories `LIL-15`, `LIL-16`,
`LIL-64`), plus the iOS silent `defaultOnDisk`-fallback detail folded into
`LIL-15`. Added the canonical `StoreLocation` resolver
(`Packages/LillistCore/Sources/LillistCore/Persistence/StoreLocation.swift`)
— a `Role` enum (`mainApp`/`extensionProcess`/`widget`/`cli`) that is now
the single authority all six processes (iOS app, macOS app, both widgets,
both extensions, the CLI) use to resolve the shared store path
(`<group>/Lillist/Lillist.sqlite`, identical for every role) and to decide
whether CloudKit mirroring may be armed (only `.mainApp`, via the new
`StoreConfiguration.armsCloudKitMirroring` field). Retired
`StoreConfiguration.appGroupOnDisk` (superseded, last caller — iOS — moved
off it) and the CLI's own third divergent path.

Added `MacAppGroupMigration` — a one-time, pure-file-system migration that
runs before macOS's `AppEnvironment.make()` constructs any
`PersistenceController`: copies the legacy sandbox Application Support
store into the App Group location (staged + byte-size-verified before
either live store is touched), quarantines the legacy original (moved,
never deleted). The both-stores-populated edge case (reachable if this
Mac's widget already ran under the pre-fix `X1` bug) is resolved by a
council-vote-decided `SyncMode`-conditioned policy: `.iCloudSync`
quarantines the App-Group store and migrates legacy into its place;
`.localOnly` makes **zero file mutation** (no CloudKit safety net exists
for the App-Group store in that mode). Full audit trail:
`.council/macos-migration-both-stores-populated/DECISION.md`.

Full detail — per-finding fix commits/tests, the class-killer design, the
council decision's reasoning, what `3a` needs to know about
`AppEnvironment.swift`'s current shape — is in:

- Plan doc: `docs/superpowers/plans/2026-07-28-plan-1c-store-location-unification.md`
- Ledger's **Wave 1c closing report** section (in the index doc below).

Commit range: `07545d4d..e9b57e43` (10 commits: 1 docs, 6 feat/fix, 3
`chore(stories)`). Verification: full `LillistCore` suite green (1177
tests, 222 suites, up from `1b`'s 1144/219 baseline) after every commit;
`lillist-cli` builds; both apps verified with unsigned `xcodebuild` builds
(BUILD SUCCEEDED, including the widget and Share/Shortcuts extension
targets this plan touched).

## Next action

**Start Wave 1, plan `1d` (`export-schema-completeness`)** — findings
`X3 S9a X13 X18`. It does **not** sit on the `TaskStore.swift` serial chain
(that chain's next link is still `4b`) or the `AppEnvironment.swift` chain
(next link `3a`) — its hotspots are `Importer.swift`, `Exporter.swift`,
`ExportSchema.swift`, `BackupSchema.swift` (see the ledger's *Shared-file
serial chains*, chain 7 — `1d` is the first link, `2b` the second).

`1d`'s core problem (`X3`): export/import/backup silently and permanently
drop `Series`, `NotificationSpec`, and `archivedAt` — there are no DTOs for
either entity anywhere in `ExportSchema`/`BackupSchema`. Every "reset and
reseed from this device," every backup restore, and every manual
export/import permanently destroys all recurrence series, all reminders,
and all archive state, on every device that resyncs from that data.
Class-killer verdict already recorded in the ledger's *Class-killer
verdicts* table: adopt a model-derived export-completeness test (walks
`NSManagedObjectModel` so a future entity/attribute addition can't silently
skip the export schema the way `Series`/`NotificationSpec`/`archivedAt`
did).

Read the ledger's *Resume protocol* section first (confirm worktree/branch,
re-read the review + ledger, check story state, verify Wave 1c's
claimed-green state, execute, update the ledger on completion).

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
