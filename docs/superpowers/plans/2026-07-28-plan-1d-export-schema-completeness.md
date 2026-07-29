# Plan 1d — export-schema-completeness

Wave 1, plan `1d`. Findings: `X3` (`LIL-17`), `S9a` (`LIL-30`), `X13`
(`LIL-44`), `X18` (`LIL-67`). Review doc:
`docs/reviews/2026-07-28-data-sync-review.md`. Ledger:
`docs/superpowers/plans/2026-07-28-data-sync-hardening-index.md`.

## Scope note — this plan is bigger than four findings

The wave brief instructs: "add SeriesDTO + NotificationSpecDTO + `archivedAt`
(and any other silently-dropped attribute/relationship you find — the
class-killer test below is your discovery tool)." Walking the full Core Data
model (`LillistModel.xcdatamodeld`) against `ExportSchema` before writing the
completeness test surfaced two more silent drops beyond X3's own text:

1. **`SmartFilter` has zero export/backup mapping at all.** Not one field.
   It's a `syncable="YES"` CloudKit-mirrored entity exactly like `Tag` — a
   `resetAndReseedFromThisDevice`, backup restore, or manual export/import
   today permanently destroys every saved smart filter, identically to how
   X3 destroys series/reminders. This gets the same fix as Series/
   NotificationSpec: a new `SmartFilterDTO`.
2. **`AppPreferences.defaultTagTintHex` is silently dropped** — it's a real,
   CloudKit-synced, account-level preference (not part of the Plan-21
   device-local partition, see below) that `BackupRecordProjector
   .preferencesDTO` never mapped. Added to `PreferencesDTO`.

Both are squarely inside "any other silently-dropped attribute/relationship
you find" and inside the class-killer test's job description, so they're
fixed here rather than filed as new findings — this plan's own governing
test (the model walk) would otherwise fail on landing.

## Full entity/attribute/relationship disposition

Every entity in `LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`
(the model is not changed — this is a mapping-only plan per the wave brief's
constraint), attribute/relationship by attribute/relationship:

### LillistTask
All scalar attributes already mapped 1:1 into `TaskDTO` **except**:
- `archivedAt` — **added** (`TaskDTO.archivedAt: Date? = nil`). X3.
- `schemaVersion` — already mapped, unchanged.

Relationships:
- `parent` → `TaskDTO.parentID` — already mapped, unchanged (X13 fixes how
  the importer *uses* this, not the DTO shape).
- `children` — **excluded**, derived (every child task independently carries
  its own `parentID`; reconstructing `children` from the flat task list is
  the importer's job, exactly as today).
- `tags` → `TaskDTO.tagIDs` — already mapped, unchanged.
- `journalEntries` — **excluded**, derived (`JournalEntryDTO.taskID` is the
  owning direction).
- `attachments` — **excluded**, derived (`AttachmentDTO.taskID`/
  `journalEntryID` is the owning direction).
- `series` — **added** (`TaskDTO.seriesID: UUID? = nil`). This is the "many"
  side of the Series↔instances relationship, so — matching the established
  pattern (a task carries its parent's id, an attachment carries its task's
  id) — the task, not the series, carries the FK. X3.
- `seriesAsSeed` — **excluded**, derived: this is just the inverse of
  `Series.seedTask`; reconstructed from `SeriesDTO.seedTaskID` on import.
- `notificationSpecs` — **excluded**, derived: each `NotificationSpecDTO`
  carries its own `taskID` (the owning direction, matching Attachment/
  JournalEntry).

### Tag
Unchanged — already fully mapped (`id`, `name`, `tintColor`, `position`,
`parent`→`parentID`). `children`/`tasks` relationships **excluded**, derived
(same rationale as LillistTask's `children`/`tags`-inverse).

### JournalEntry / Attachment
Unchanged — already fully mapped. `Attachment.journalEntry`'s inverse
(`JournalEntry.attachments`) **excluded**, derived.

### AppPreferences
- `defaultAllDayNotificationHour`/`Minute`, `morningSummaryEnabled`/`Hour`/
  `Minute`, `trashRetentionDays`, `defaultTaskListSortRaw` — already mapped
  (renamed in the DTO: `defaultAllDayHour`/`Minute`, `defaultTaskListSort`).
- `defaultTagTintHex` — **added** (`PreferencesDTO.defaultTagTintHex: String
  = "#7F8FA6"`). Real gap — see the *Scope note* above.
- `id` — **excluded, rationale:** the row is a well-known singleton
  (`PreferencesStore.singletonID`, a fixed UUID literal); import always
  targets "the" singleton row directly, exactly like the pre-existing
  `PreferencesDTO` (which already carries no `id` field).
- `crashPromptsEnabled`, `hasCompletedOnboarding`, `quickCaptureEnabled`,
  `quickCaptureHotkey`, `statusBarItemVisible` — **excluded, rationale:**
  Plan 21 (`AppPreferencesPartitionMigrator`, `DevicePreferencesStore`)
  deliberately partitions these five fields out of the CloudKit-mirrored
  Core Data row into App-Group `UserDefaults`, specifically *so that* a
  destructive sync-mode migration or reset cannot wipe a value the user
  expects to stay device-local (`DevicePreferencesStore.swift`'s own doc
  comment). The Core Data columns are documented migration-compat
  scaffolding (`AppPreferencesPartitionMigrator.swift`: "intentionally not
  removed from the model... legacy code paths that have not yet migrated"),
  not the design's source of truth going forward. Excluding them from
  export/backup is the *design's own intent*, not an oversight — this
  matches the pre-existing `PreferencesDTO` shape (it already omitted these
  five before this plan touched anything).

  **Discovered, out-of-scope wiring inconsistency (flagged, not fixed
  here):** `CrashReportingSection`/`CrashReportingPane` still bind
  `PreferencesStore.Prefs.crashPromptsEnabled` (the Core-Data-backed field)
  for the Settings toggle and write the whole `Prefs` struct back through
  `PreferencesStore.update`, while `AppEnvironment.crashPromptsEnabled` (what
  `CrashReporterHost` actually reads at boot) initializes from
  `DevicePreferencesStore` and the toggle's `.onChange` only mirrors into the
  in-memory `environment.crashPromptsEnabled` — never persisting to
  `DevicePreferencesStore`. That looks like a real, live defect (a user's
  crash-prompt choice may not survive relaunch) but it's a preferences-
  partition wiring bug, not an export-completeness bug, and touching it here
  would conflate an unrelated behavior change with this plan's scope.
  Reported to `team-lead` for triage into an existing or new finding.

### SmartFilter
Entire entity **added** (`SmartFilterDTO`) — see *Scope note* above. All 9
attributes mapped 1:1 (`predicateGroupJSON` decoded into a typed
`PredicateGroup?`, matching `Series.rule`'s resilience pattern — `try?`
decode, `nil` on malformed JSON rather than throwing). No relationships to
map (`SmartFilter` has none).

### Series (new)
Entire entity **added** (`SeriesDTO`). `id`, `ruleJSON`→`rule:
RecurrenceRule?` (typed, `try?` decode), `nextOccurrenceAfter` mapped
directly. `seedTask` → `SeriesDTO.seedTaskID: UUID?` (owning direction,
matching `Series.seedTask` being the "one" side documented from the Task
side too via `TaskDTO.seriesID`, deliberately redundant with the reverse FK
so a partial/lossy scan of either side still reconstructs the relationship —
see *Import wiring* below for why both directions are populated).
`instances` **excluded**, derived (reconstructed from every `TaskDTO` whose
`seriesID` matches).

### NotificationSpec (new)
Entire entity **added** (`NotificationSpecDTO`). `id`, `kindRaw`→`kind: Int`
(raw, matching `TaskDTO.status`/`JournalEntryDTO.kind`/`AttachmentDTO.kind`'s
existing raw-int convention rather than the typed enum), `offsetMinutes`,
`fireDate`, `snoozedUntil`, `createdAt` mapped directly. `task` →
`NotificationSpecDTO.taskID: UUID?` (owning direction, matching Attachment/
JournalEntry).

**`lastFiredAt` — decided directly, no council needed.** Round-trips as-is;
import does **not** reset it to `nil`. Rationale, from reading the actual
consumer (`NotificationScheduler.computeDesiredRequests`,
`NotificationScheduler.swift:169-209`):
`lastFiredAt` is already a real CloudKit-mirrored field — its whole purpose
(per the existing code comment at `NotificationScheduler.swift:180-188` and
`RemoteChangeReconciler.swift:6-9`) is cross-device de-dup: "Device A fires
locally, writes `lastFiredAt`; Device B learns via CloudKit sync and drops
its own pending request for the same fire time." The de-dup guard is
`lastFired >= fireDate - 60s`, and it is only ever consulted when `fireDate >
Date()` (line 194 short-circuits past-due fire dates regardless of
`lastFiredAt`) — so resetting it on import would only change behavior for a
spec whose fire time is still in the future *and* already fired, an edge
case the field exists specifically to get right. `resetAndReseedFromThisDevice`
converges every other device on *this* device's exact state by design (the
whole point of the operation) — reproducing `lastFiredAt` faithfully is the
*correct* converge-to-truth behavior, identical in kind to reproducing
`closedAt`/`deletedAt`. No design document (unlike the AppPreferences
device-partition case) declares this field device-local or export-exempt.
The counter-argument ("dropping it lets an already-delivered reminder
re-fire, which is at worst a duplicate ping, never data loss") does not
survive contact with the guard's actual short-circuit at line 194 — a
concrete refutation, not a coin flip — so this does not meet the "2+
defensible alternatives" bar for `council:council-vote`.

## New DTOs (`ExportSchema.swift`)

```swift
public struct SeriesDTO: Codable, Sendable, Equatable {
    public var id: UUID
    public var seedTaskID: UUID?
    public var rule: RecurrenceRule?
    public var nextOccurrenceAfter: Date?
}

public struct NotificationSpecDTO: Codable, Sendable, Equatable {
    public var id: UUID
    public var taskID: UUID?
    public var kind: Int
    public var offsetMinutes: Int32?
    public var fireDate: Date?
    public var lastFiredAt: Date?
    public var snoozedUntil: Date?
    public var createdAt: Date?
}

public struct SmartFilterDTO: Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var predicateGroup: PredicateGroup?
    public var tintColor: String?
    public var sortField: String
    public var sortAscending: Bool
    public var isPinned: Bool
    public var position: Double
    public var createdAt: Date?
    public var modifiedAt: Date?
}
```

`Document` gains `series: [SeriesDTO] = []`, `notificationSpecs:
[NotificationSpecDTO] = []`, `smartFilters: [SmartFilterDTO] = []` (appended
at the end, defaulted — preserves every existing Swift call site that
constructs `Document` positionally-by-keyword without these three).
`TaskDTO` gains `archivedAt`/`seriesID` appended after `schemaVersion`, same
defaulting discipline. `PreferencesDTO` gains `defaultTagTintHex` appended
last.

## Version-compat matrix

`ExportSchema.version` bumps **1 → 2**. The existing forward-incompatibility
guard in `Importer.apply` (`document.version <= ExportSchema.version`,
otherwise `.unsupportedExportVersion`) is untouched — it already does the
right thing once `version` is 2.

| Reader | Bundle | Outcome |
|---|---|---|
| New importer (v2) | Old bundle (v1) | **Applies.** `Document`, `TaskDTO`, `PreferencesDTO` each get a custom `init(from:)` (extending the existing `TaskDTO`/`schemaVersion` pattern) that `decodeIfPresent`s every new key, defaulting absent ones to `[]`/`nil`/`"#7F8FA6"`. No behavior change to existing fields. |
| New importer (v2) | New bundle (v2) | Applies, full fidelity, including series/notificationSpecs/smartFilters/archivedAt/defaultTagTintHex. |
| Old importer (v1, hypothetical) | New bundle (v2) | **Rejected** — `document.version (2) > ExportSchema.version (1)` on the old build throws `.unsupportedExportVersion`. Unchanged mechanism, verified with a bumped-version fixture (mirrors the existing `versionNewerThrows` test). |

`BackupPackageSchema.version` (the on-disk *layout* version, independent per
its own doc comment) bumps **1 → 2**: `TaskBackupRecord` gains
`notificationSpecs: [NotificationSpecDTO] = []` (task-owned, so it lives in
the per-task file, not a sidecar), and the package gains two new
sidecar files, `series.json` / `smartFilters.json`, alongside the existing
`tags.json`/`preferences.json` (matching `TaskBackupStore`'s own doc
comment: "Shared entities (tags, preferences) live in sidecar files" — Series
and SmartFilter are shared/account-level, not owned by one task, so they
follow tags' precedent rather than notificationSpecs'). `TaskBackupRecord`
gets the identical decode-with-default treatment as `Document`/`TaskDTO` for
old-package compatibility. `BackupPackageReader.readSeries()`/
`readSmartFilters()` return `[]` when the sidecar file is absent (mirrors
`readTags()`/`readPreferences()`'s existing missing-file handling).

## `.skipExisting` semantics (X13)

Current bug, reproduced directly: the second pass that wires
`.parent`/tag-`.parent` runs unconditionally over **every** DTO in the
bundle, because `taskByID`/`tagByID` are populated for skipped rows too (the
assignment happens right after the switch, for all three outcomes). Two
distinct symptoms, one root cause:

1. A row explicitly left alone by `.skipExisting` still gets its `.parent`
   silently rewritten by the second pass.
2. Parent resolution only ever consults the bundle's own row set
   (`taskByID`/`tagByID`), never the destination store — so a parent that
   legitimately exists in the destination but isn't part of *this* bundle
   (a partial/targeted import) is treated as "missing," silently promoting
   an otherwise-correctly-inserted-or-updated child to root.

**Fix — both halves, for both tasks and tags** (the wave brief: "same
question applies to tags' parents — check and cover it"):

| Policy | Outcome | Second-pass behavior |
|---|---|---|
| `.skipExisting`, row pre-existing | `.skip` | Row (including `.parent`) is **never touched** by any pass. |
| `.replaceExisting` / `.recencyWins`, row pre-existing, action resolves to update | `.update` | `.parent` **is** rewritten from the incoming DTO — this is the intended "replace" contract. |
| Any policy, row newly inserted | `.insert` | `.parent` is wired from the incoming DTO. |
| `.parent` resolution, any of the above non-skip cases | — | Resolve within the bundle's own row set first; if absent there, **fall back to a destination-store fetch by id** before concluding the parent doesn't exist. Only promote to root if neither resolves. |

Mechanism: track `skippedTaskIDs`/`skippedTagIDs: Set<UUID>` alongside the
existing `taskByID`/`tagByID` dictionaries during the first pass; the second
pass `guard`s on non-membership before touching `.parent`, and resolves via
`taskByID[parentID] ?? (try? fetchTask(id: parentID, ctx: ctx))` (same
pattern for tags). The new `Series`/`NotificationSpec` wiring (below) is
designed with this same discipline from the start, so it doesn't reproduce
X13's shape for the relationships this plan adds.

## Import wiring order (X3 + X13, `Importer.apply`)

Sequenced to respect every relationship's data dependency:

1. Tags: create/update/skip (unchanged) → wire `.parent` (X13-fixed).
2. Tasks: create/update/skip via `applyTask` (now also sets `.archivedAt`;
   still resolves `tagIDs` inline, unchanged) → wire `.parent` (X13-fixed).
3. Journal entries: unchanged (owner resolution already correct).
4. **Series** (new): create/update/skip by id, tracking `skippedSeriesIDs` →
   wire `.seedTask` (bundle-then-store fallback, skip-respecting) → wire
   `Task.series` for every non-skipped task DTO with a non-nil `seriesID`
   (resolves via `seriesByID` with a destination-store fallback, mirrors
   parent-resolution discipline). A `seedTaskID` that resolves nowhere
   leaves `series.seedTask = nil` (Core Data allows this — the relationship
   is optional) rather than dropping the whole series: the series' `rule`/
   `nextOccurrenceAfter` and its instance tasks (wired independently via
   `seriesID`) remain valid and far more valuable to preserve than a single
   dangling seed pointer; an error is still recorded so the anomaly isn't
   silent.
5. **NotificationSpec** (new): create/update/skip by id, each wired to its
   `taskID` directly at creation time (simple owned-child pattern, same
   shape as Attachment/JournalEntry — no second pass needed). An
   unresolvable `taskID` (neither bundle nor store) skips the row with a
   recorded error, matching the existing JournalEntry/Attachment orphan
   convention.
6. Attachments: unchanged.
7. **SmartFilter** (new): create/update/skip by id — standalone, no
   relationships to wire.
8. Single `ctx.save()` — unchanged all-or-nothing transaction contract.

## X18 — reconciling the finding text with the current code

The review's literal description ("Export performs 4 independent fetches...
producing a torn bundle") does **not** match `Exporter.swift` as it stands
today: the four fetches (task/tag/journal/attachment) are already inside one
`ctx.perform` block, and have been since an earlier, unrelated refactor
(`25b8de94 refactor(export): run Exporter reads on a background context`,
which predates this review). The wave brief's own prescribed fix — "all
fetches inside ONE `ctx.perform` block" — is already satisfied by that
shape.

What is **not** already satisfied, and is a live instance of the exact defect
X18 describes: `Exporter.buildDocument` calls `preferences.read()` — a fifth
data source, uncounted by the review's "4" but structurally identical —
*before* `ctx.perform` even begins, via `PreferencesStore`'s own separate
`context.perform` on the **view context**, a different context entirely. A
concurrent write (local or CloudKit-merged) landing between that call and the
background-context fetch block produces exactly the described torn bundle,
just for preferences instead of tasks/journal entries.

**Fix:** fetch `AppPreferences` (by `PreferencesStore.singletonID`) directly
from the *same* `ctx`, *inside* the *same* `ctx.perform` block as every other
fetch — including the three new ones this plan adds (series,
notificationSpecs, smartFilters) — rather than through `PreferencesStore`.
`Exporter` keeps its `preferences: PreferencesStore` constructor parameter
unchanged (no public API break across the ~10 call sites in both apps, the
CLI, and tests) even though the instance is no longer read from directly for
this path; a doc comment on the property explains why.

**Sibling sweep (not X18 itself, but the identical defect shape, in a file
this plan already extensively rewrites for series/smartFilters sidecar
support):** `LocalBackupCoordinator.reconcileFull()` and `.refreshSidecars()`
both call `preferences.read()` before their own `ctx.perform` block, for the
same reason. Fixed the same way, in the same edit that adds series/
smartFilters fetching to those two functions — not treated as a fifth
finding, logged here per "fix any hits unless distant and unrelated."

**What "already-fixed" means for verification:** no test can prove a fetch
race *didn't* happen; the regression coverage here proves the *structural*
property instead — every value in the exported document (including the new
DTOs) comes from fetches lexically inside one `ctx.perform` block using one
context, and `preferences.read()` is no longer called from `Exporter`'s
export path at all (a compile-time-checkable, not just runtime-checkable,
guarantee once the call is deleted).

## S9a

One-line fix at `DataStoreResetService.resetAndReseedFromThisDevice`
(`Sync/DataStoreResetService.swift:202`): pass
`assetsDirectory: tempDir.appendingPathComponent("assets", isDirectory:
true)`, mirroring `BackupRestoreService.restore(from:)`'s existing, correct
call (`Backup/BackupRestoreService.swift:121-125`, `reader.assetsDirectory`).
`Exporter.export(to:)` already writes attachment bytes under
`<dir>/assets/`; the importer's attachment branch was simply never told
where to find them on this one call path.

## Class-killer: model-derived completeness test

New suite, `ExportSchemaCompletenessTests` (`Export/` test directory).
Walks `PersistenceController.sharedModel()` — every `NSEntityDescription`,
every `attributesByName`/`relationshipsByName` key — and for each one:

1. Looks up a per-entity table of `(renames: [String: String], excluded:
   [String: String])` — renames map a Core Data name to the DTO field name
   when they differ (e.g. `statusRaw` → `status`, `ruleJSON` → `rule`); the
   excluded dict maps a Core Data name to a **required, non-empty rationale
   string** (the *Full entity/attribute/relationship disposition* section
   above is the source of truth these strings are drawn from).
2. Reflects the corresponding DTO type's stored-property names via `Mirror`
   (e.g. `SeriesDTO` for `Series`, `TaskDTO` for `LillistTask`).
3. Asserts every Core Data name is *either* present (after rename) in the
   DTO's reflected field set *or* present in the exclusion table — anything
   in neither bucket fails the test by name, pointing straight at the gap.

This directly generalizes the pattern that caught `SmartFilter`/
`defaultTagTintHex` above: adding a new entity or attribute to the Core Data
model without updating either the schema or the exclusion table fails this
test immediately, by design.

**Class-kill demonstration (per house rules — run once locally, not
committed):** temporarily removed `SmartFilter`'s entry from both the
schema-mapping and the exclusion table, confirmed the test fails naming
`SmartFilter`'s attributes specifically (not a generic failure), then
restored it and confirmed `git status` was clean before continuing.

## Verification gate

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/LillistCore --parallel --num-workers 2
```
Baseline to not regress: 1177 tests / 222 suites (Wave 1c's closing count).

## CloudKit-visible schema implications

**None.** Every change in this plan is to the export/backup *file format*
(`ExportSchema`, `BackupPackageSchema` — plain Codable structs serialized to
JSON) and to `Importer`/`Exporter`/`LocalBackupCoordinator`'s in-process
logic. The Core Data model (`LillistModel.xcdatamodeld`) is unchanged, so
there is nothing to deploy Development→Production in the CloudKit Console
for this plan.
