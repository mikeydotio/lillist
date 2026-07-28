# HANDOFF — Data & Sync Hardening, Wave 1d → Wave 2a

**Worktree:** `/Volumes/Code/mikeyward/Lillist/.claude/worktrees/data-sync-hardening`
**Branch:** `hardening/data-sync-2026-07`
**State:** Wave 0 (docs + stories) and **all of Wave 1** (`1a`
`trash-tree-integrity`, `1b` `purge-cloudkit-retirement`, `1c`
`store-location-unification`, `1d` `export-schema-completeness`) are
**COMPLETE**. Waves 2 through 6 not started.

## What landed this wave (plan `1d`)

All 4 findings closed (`X3`, `S9a`, `X13`, `X18` / stories `LIL-17`,
`LIL-30`, `LIL-44`, `LIL-67`). Scope grew beyond the four named findings:
walking the full Core Data model against `ExportSchema` (required to build
the completeness test) surfaced two more silent drops — `SmartFilter` had
**zero** export/backup mapping at all, and `AppPreferences
.defaultTagTintHex` (a real, CloudKit-synced field, distinct from Plan 21's
five device-local fields) was never mapped. Both fixed alongside `X3`. A
third gap surfaced while writing the round-trip test itself:
`BackupRestoreService.applyPreferences` never copied `defaultTagTintHex`
either — fixed in the same commit, verified red→green by temporarily
reverting the one-line fix.

`ExportSchema.version` and `BackupPackageSchema.version` both bumped 1→2.
New `SeriesDTO`/`NotificationSpecDTO`/`SmartFilterDTO`;
`TaskDTO.archivedAt`/`.seriesID`; `PreferencesDTO.defaultTagTintHex`. Every
addition decode-with-default on an older bundle (verified with a
hand-written v1 JSON fixture, not just a Swift default value); the
forward-incompatibility guard is unchanged and still correctly rejects a
newer bundle. `Importer.apply` extends `X13`'s skip-respecting,
bundle-then-store-fallback discipline to the two new relationships
(`Series.seedTask`, `Task.series`) from the start — a fresh relationship
never reproduces the shape `X13` just fixed for `.parent`.

`X13` fix: the second pass wiring `.parent` ran unconditionally over every
DTO, including rows `.skipExisting` explicitly left alone, and only ever
resolved a parent within the bundle's own row set (never the destination
store) — both fixed, for tasks and tags.

`S9a` fix: `Importer.importBundle(at:conflictPolicy:)` had no
`assetsDirectory` parameter *at all*, so every caller — not just
`resetAndReseedFromThisDevice` — silently dropped every attachment on
import. Added the parameter and wired it at all three real call sites,
including two more sibling instances found by grep: the iOS/macOS Settings
"Import a Backup" flows.

`X18` fix: the review's literal "4 independent fetches" description didn't
match the current code (already consolidated into one `ctx.perform` block
by an earlier, unrelated refactor). What *was* still broken: `Exporter`
read `AppPreferences` via a separate `PreferencesStore.read()` round trip,
on a different context, before that `ctx.perform` block even started — a
live instance of the same torn-bundle defect, just for preferences.
Fixed by fetching `AppPreferences` directly inside the same background
context/perform block as every other fetch. Sibling-swept the identical
pattern in `LocalBackupCoordinator`.

Class-killer delivered: `ExportSchemaCompletenessTests.modelCompleteness`
walks every entity in the live Core Data model and asserts each
attribute/relationship is mapped into a DTO field (directly or via a
documented rename) or on an explicit, rationale'd exclusion list. Kill
demonstrated locally (not committed): removed `SmartFilter`'s mapping
entry, confirmed the failure names `SmartFilter` specifically, restored.

**Discovered, flagged, NOT fixed (out of `1d`'s scope):**
`CrashReportingSection`/`CrashReportingPane` still bind
`PreferencesStore.Prefs.crashPromptsEnabled` (Core-Data-backed) for the
Settings toggle, while `AppEnvironment.crashPromptsEnabled` (what
`CrashReporterHost` actually reads at boot) initializes from
`DevicePreferencesStore` and the toggle never persists back to it — a
user's crash-prompt choice may not survive relaunch. Reported to
`team-lead` for triage into an existing or new finding.

Full detail — per-finding fix commits/tests, the version-compat matrix,
the `lastFiredAt` decision, what `2b` needs to know about
`ExportSchema`/`BackupPackageSchema`'s current shape — is in:

- Plan doc: `docs/superpowers/plans/2026-07-28-plan-1d-export-schema-completeness.md`
- Ledger's **Wave 1d closing report** section (in the index doc below).

Commit range: `8d1472fb..2b1b7ad2` (7 commits: 1 docs, 2 fix, 1 feat, 1
test, 2 `chore(stories)`). Verification: full `LillistCore` suite green
(1195 tests, 225 suites, up from `1c`'s 1177/222 baseline) after every
commit; `lillist-cli` builds; both apps verified with unsigned `xcodebuild`
builds (BUILD SUCCEEDED). No CloudKit-visible schema implications — the
Core Data model is unchanged.

## Next action

**Start Wave 2, plan `2a` (`migration-transitions`)** — findings `S1 S5 S6
S8 S11 S12 S14 S15 S16 S17`. Its hotspots are `MigrationCoordinator.swift`
and `PersistenceHost.swift` (see the ledger's *Shared-file serial chains*,
chains 2 and 3 — `2a` is the first link in both; `2b` follows on chain 2,
then `3a`). `2a` is also the first plan to introduce the new
`DestructiveOpGate` public type — per house rules, that needs a
type-system proposal + UML diagram in its plan doc before implementation
(see the ledger's *Class-killer verdicts* table).

Read the ledger's *Resume protocol* section first (confirm worktree/branch,
re-read the review + ledger, check story state, verify Wave 1's
claimed-green state, execute, update the ledger on completion), then the
*Wave 1d closing report* for the `ExportSchema`/`BackupPackageSchema` v2
shape now in place, which `2b` (not `2a`, but worth knowing about early
since it's the next link on chain 7) will build on.

## Standing worktree rules (unchanged)

No merge, no `/semver bump`, no `/deployit deploy` from this worktree.
One PR opens at the very end of Wave 6 — this session stops after opening
it, per policy.
