# Lillist — Design Document

**Date:** 2026-05-12
**Status:** Approved for implementation planning
**Author:** Mikey Ward (with Claude)

## Overview

Lillist is a macOS / iOS / iPadOS task management app in the spirit of Things 3, with a CLI for scriptability and several deliberate divergences:

- **Pure-nesting data model.** Everything is a Task; arbitrary depth. "Projects" and "Areas" do not exist as separate entities — tags fill that role.
- **CloudKit sync** via `NSPersistentCloudKitContainer`.
- **First-class CLI** (`lillist`) with feature parity. Both the GUI and CLI are clients of the same local Core Data store.
- **Status + journal stream per task** (Jira-lite). Statuses: `Todo / Started / Blocked / Closed`. Journal entries are timestamped notes, status transitions, and attachment additions.
- **Rich attachments** — images, files, and unfurled link previews.
- **Robust tagging** with nested single-parent hierarchy, tint colors, and a smart-filter rule engine.

This document captures the v1 design. The implementation plan derives from it via the `writing-plans` workflow.

---

## 1. Platforms, Targets, and Build Topology

**Platforms (v1):** macOS, iOS, iPadOS. The CLI ships with the macOS app (also available via Homebrew tap). No Linux/Windows CLI in v1.

**Minimum OS:** macOS 15, iOS 18, iPadOS 18. Modern SwiftUI, `@Observable`, App Intents, Swift Testing.

**Language/frameworks:**
- Swift 6 with strict concurrency in `LillistCore`.
- SwiftUI for app UI; AppKit interop only where unavoidable (status bar, global hotkey, drag-and-drop edge cases).
- `swift-argument-parser` for the CLI.
- `NSPersistentCloudKitContainer` for persistence + sync.

**Project structure:**

```
Lillist/
├── Lillist.xcworkspace
├── Packages/
│   ├── LillistCore/          # SPM — model, persistence, sync, business logic
│   │   ├── Sources/Model/
│   │   ├── Sources/Persistence/
│   │   ├── Sources/Rules/
│   │   ├── Sources/Recurrence/
│   │   ├── Sources/Notifications/
│   │   ├── Sources/Search/
│   │   └── Sources/CLIBridge/
│   └── LillistUI/            # SPM — SwiftUI components shared across platforms
├── Apps/
│   ├── Lillist-macOS/
│   ├── Lillist-iOS/
│   └── lillist-cli/
└── Extensions/
    ├── ShareExtension-iOS/
    └── ShortcutsActions/
```

`LillistCore` is the integrity boundary for the "CLI has feature parity" promise: if it's a method on `LillistCore`, every client has it.

---

## 2. Data Model

Core Data managed objects backed by `NSPersistentCloudKitContainer`. UUIDs everywhere.

### Task

The central entity. Everything is a task.

- `id: UUID`
- `title: String`
- `notes: String` — top-level Markdown notes, distinct from journal entries.
- `status: Status` — enum `todo | started | blocked | closed` (stored as Int16).
- `start: Date?`, `startHasTime: Bool` — date-only when `startHasTime == false`.
- `deadline: Date?`, `deadlineHasTime: Bool`
- `parent: Task?` (cascade-delete)
- `children: [Task]` — ordered by `position`.
- `position: Double` — fractional ordering within parent; gap-based.
- `tags: [Tag]` — many-to-many.
- `isPinned: Bool`
- `series: Series?` — non-nil for recurring instances.
- `createdAt: Date`, `modifiedAt: Date`
- `deletedAt: Date?` — non-nil = in Trash; auto-purged after retention.
- `closedAt: Date?` — managed automatically by status transitions.

### Tag

- `id: UUID`
- `name: String` — unique among siblings (validated in business logic).
- `parent: Tag?`
- `children: [Tag]`
- `tintColor: String` — hex.
- `position: Double` — manual order among siblings.

### JournalEntry

Every change-of-record lives here.

- `id: UUID`
- `task: Task` (cascade-delete)
- `kind: Kind` — enum `note | statusChange | attachment | createdFollowUp`.
- `body: String` — Markdown. Required for `note`, optional for system kinds (auto-generated).
- `payload: Data?` — type-specific structured JSON:
  - `statusChange`: `{from, to}`
  - `attachment`: attachment metadata
  - `createdFollowUp`: `{followUpTaskID}`
- `createdAt: Date`
- `editedAt: Date?` — null until first edit; system entries reject edits.

### Attachment

Referenced from `JournalEntry` where `kind == attachment`. `CKAsset`-backed.

- `id: UUID`
- `journalEntry: JournalEntry` (cascade-delete)
- `task: Task` — denormalized for indexing in the "attachments area" UI.
- `kind: Kind` — `image | file | linkPreview`.
- `filename: String`
- `uti: String` — UTType.
- `byteSize: Int64`
- `asset: CKAsset?` — nil for `linkPreview`.
- `linkPreview: LinkPreviewPayload?` — `{url, title, description, thumbnailAssetURL, favicon, fetchedAt}`.

### Series

Recurrence rule + shared metadata. Calendar/Reminders edit-this-vs-all-future model.

- `id: UUID`
- `rule: RecurrenceRule` (JSON-encoded value type)
  - `type: calendar | afterCompletion`
  - `calendar` variant: RRULE-subset (`freq`, `interval`, `byDay`, `byMonthDay`, `bySetPos`, `count?`, `until?`).
  - `afterCompletion` variant: `{interval: TimeInterval}`.
- `seedTask: Task?` — source-of-truth for "edit all future."
- `nextOccurrenceAfter: Date?` — cached.

Mechanics:
- Completing an instance spawns the next, copying the seed's editable fields. Children of the seed are deep-copied per instance.
- "Edit this one" → modifies the single instance.
- "Edit all future" from a non-seed instance → forks the Series. Old Series keeps existing instances; new Series spawns from the fork point.

### SmartFilter

Saved live query.

- `id: UUID`
- `name: String`
- `predicateGroup: PredicateGroup` (JSON-encoded; recursive for v2 nested groups, flat in v1 UI)
- `tintColor: String?`
- `sortField: SortField`, `sortAscending: Bool`
- `isPinned: Bool`
- `position: Double`

### NotificationSpec

- `id: UUID`
- `task: Task` (cascade-delete)
- `kind: defaultStart | defaultDeadline | offsetStart | offsetDeadline | nudge`
- `offsetMinutes: Int?`
- `fireDate: Date?` — for nudges.
- `lastFiredAt: Date?` — for cross-device de-dup.
- `snoozedUntil: Date?`

### AppPreferences

Singleton, CloudKit-private.

- `defaultAllDayNotificationTime: DateComponents`
- `morningSummaryEnabled: Bool`, `morningSummaryTime: DateComponents`
- `trashRetentionDays: Int` — default 30.
- `defaultTaskListSort: SortField`

### Invariants (enforced in `LillistCore`, not the DB)

- A task's `parent` cannot transitively be itself.
- Series with `count`/`until` reached do not spawn further.
- Tag names unique among siblings; rename conflicts auto-suffix " (2)".
- `closedAt` managed automatically.
- No reserved tasks (no Inbox). Trash is a query over `deletedAt != nil`.

---

## 3. Sync, Storage, and Migrations

### Container topology

One CloudKit container (`iCloud.com.mikeydotio.lillist`), private database, one custom zone (`Lillist`). Custom zone for zone-wide changesets, atomic batch deletes, and future "shared" zone optionality.

### Schema mirroring

`NSPersistentCloudKitContainer` mirrors the Core Data model automatically. CloudKit dev schema initialized from the model on boot in DEBUG; production promoted manually before each releasing change.

### Merge policy

- `NSMergeByPropertyObjectTrumpMergePolicy` — last writer wins per *field*.
- Journal entries effectively immutable from a merge perspective.
- Deletes propagate as deletes. Soft-deletes are just field writes; concurrent delete + edit converges to "in Trash with edits intact."

### Ordering under sync

`position` is a `Double` with gap-based insertion: `(left.position + right.position) / 2`. A background compaction job re-spaces siblings when gaps shrink below threshold. Concurrent reorders converge to *some* deterministic order; no data loss.

### Attachments

`CKAsset` storage in the same zone as the owning record (CloudKit requirement). Core Data binary attribute marked "Allows External Storage."

- iOS/iPadOS: lazy download. Metadata available immediately; bytes load on first access. Per-device cache.
- Upload progress surfaced via `Progress` for assets > ~1 MB.

### Link previews

Async pipeline:
1. Create the `JournalEntry` + `Attachment` (kind=`linkPreview`, status=`fetching`) immediately.
2. Background `URLSession` job: download page, parse OG/Twitter card, fetch thumbnail to `CKAsset`.
3. On success, update row with unfurled metadata. On failure, leave raw URL with "couldn't fetch" affordance and retry button.

Per-fetch limits: 10s hard timeout, 5 MB body cap, HTML-only parsing (no JS execution).

### Offline behavior

Writes go to local SQLite first. Sync runs in background. UI never blocks on sync. A small sync-status indicator in the sidebar shows last successful sync time and persistent errors.

### Schema migrations

Lightweight (auto-inferable) preferred; hand-written mapping models otherwise. CloudKit schema migrations are **additive only** — never rename/remove a released field; deprecate-and-ignore instead.

### Data export

`LillistCore` exposes an export API producing JSON + an asset folder. CLI: `lillist export <dir>`. macOS app: File menu. Export-only in v1; no import (no source to import from yet).

### CloudKit-specific accommodations

- No required CloudKit fields; required-ness validated in business logic.
- No `to-one` deny rules in Core Data; deletion guards replicated in business logic.
- Account states handled explicitly: *Available*, *No account*, *Restricted*, *Account changed*. See Section 8.

---

## 4. Notifications, Snooze, and Nudges

### Stack

`UNUserNotificationCenter` on all three platforms. `LillistCore.NotificationScheduler` maps `NotificationSpec` rows to scheduled requests.

> **Revision (2026-06-17): no default notifications.** Setting a `start` or
> `deadline` no longer auto-schedules anything. The `defaultStart` /
> `defaultDeadline` spec kinds are no longer materialized by the scheduler
> (and legacy ones are purged on reconcile) — only **user-added** reminders
> fire. Layers 1–2 below are retained as history; their *machinery* (all-day
> resolution to the default time, DST-safe triggers) lives on and now shapes
> user reminders placed on all-day tasks, but nothing is created automatically.

### Layers

1. ~~**Time-bearing dates auto-schedule.**~~ *(removed — see revision above)*
2. ~~**All-day dates use the user's default time.**~~ *(no longer auto-created; the default time still resolves all-day **user** reminders.)*
3. **Per-task reminders (now the only scheduling source).** One or more `NotificationSpec`s of kind `offsetStart` / `offsetDeadline` (with `offsetMinutes`) relative to the anchor. UI exposes "Add reminder" with quick presets; the data model permits arbitrary offsets.
4. **Morning summary.** Daily repeating trigger at user-configured time. Body computed at delivery from `LillistCore`.
5. **Nudges.** First-class `NotificationSpec` of kind `nudge` with an absolute `fireDate`. Independent of start/deadline.

### Cross-device de-duplication

- Each device schedules its own local notification, tagged with `"\(specID)#\(deviceFingerprint)"`.
- On firing, write `lastFiredAt` to the spec.
- Other devices observe the change via CloudKit sync, remove the matching pending notification before it fires.
- Acceptable race window: a few seconds. v2 can tighten via CloudKit subscriptions delivering APNs pushes.
- Morning summary fires independently on each device (feature, not bug).

### Snooze

- `SnoozeAction` value type: `{id, displayName, compute: (NotificationSpec, deliveredAt) -> Date}`.
- `SnoozeRegistry` holds the active set.
- v1 actions: `tenMinutes`, `oneHour`, `tomorrowMorning` (uses default all-day time).
- v2: custom durations via "Snooze for…" sheet — purely additive.

### Blocked-status follow-up affordance

When a user transitions to Blocked, the task detail surfaces an inline "Schedule follow-up" form:
- Title (placeholder pre-fills "Follow up on '<parent title>'").
- Deadline (defaults to tomorrow 9am).
Submitting creates a **sibling** task (same parent), `status=todo`, with the title/deadline; the blocked task gets a `createdFollowUp` journal entry linking to it.

Sibling rather than child so collapsing the blocked task doesn't hide the follow-up. Drag-reparent if desired.

### Status transitions are notification-aware

- → `Closed`: cancel all pending deliveries (spec rows preserved for history).
- ← `Closed`: re-register any still-future specs.
- → `Blocked`: notifications **not** suppressed.

### Permissions

First-launch authorization request with a one-screen explanation. Denial → in-app banner with Settings deep-link.

---

## 5. Smart Filters & The Rule Engine

### Predicate shape

```swift
indirect enum Predicate: Codable {
    case leaf(Leaf)
    case group(PredicateGroup)
}

struct PredicateGroup: Codable {
    enum Combinator: String, Codable { case all, any }
    var combinator: Combinator
    var predicates: [Predicate]
}

struct Leaf: Codable {
    var field: Field
    var op: Op
    var value: Value
}
```

Recursive type lays runway for v2 nested groups; v1 UI is flat-only.

### Field set

| Field | Operators |
|---|---|
| `title` | `contains`, `equals`, `startsWith` (case+diacritic insensitive) |
| `notes` | `contains` |
| `journalText` | `contains` (searches `note`-kind entries) |
| `tag` | `includesAny`, `includesAll`, `excludesAll`; descendants implicit by default with `includeDescendants` toggle |
| `status` | `is`, `isNot` |
| `start` | `before`, `after`, `on`, `withinLastDays`, `withinNextDays`, `isSet`, `isUnset` |
| `deadline` | same as `start` |
| `createdAt` | `before`, `after`, `on`, `withinLastDays`, `equalsModifiedAt` |
| `modifiedAt` | `before`, `after`, `on`, `withinLastDays` |
| `closedAt` | `before`, `after`, `on`, `withinLastDays`, `isSet`, `isUnset` |
| `hasAttachments` | `is` (bool); optional `ofKind` |
| `hasChildren` | `is` (bool) |
| `hasNudges` | `is` (bool) |
| `isPinned` | `is` (bool) |
| `ancestor` | `isDescendantOf`, `isAncestorOf` |
| `recurrence` | `isRecurring` (bool) |
| `inTrash` | `is` (bool) |

### Date values

Two forms:
- **Absolute:** a `Date`.
- **Relative DSL:** `today`, `tomorrow`, `yesterday`, `+7d`, `-2w`, `startOfWeek`, `endOfMonth`. Stored as structured value; resolved at evaluation time so "next 7 days" always means *now's* +7.

### Evaluation

Two parallel paths:

1. **`NSPredicate` translation** — backs live smart filter views via `NSFetchedResultsController`. Subquery-shaped predicates for `journalText`, `tag.includesAll`, `ancestor`.
2. **Pure-Swift evaluator** — used for in-memory checks (badge counts on pinned filters) and the CLI when filtering large query results.

Both paths share a comprehensive fixture suite; tests fail if they diverge. This is the regression backbone.

### Trash handling

Implicit `inTrash is false` predicate appended unless filter explicitly sets `inTrash`.

### Sort

A filter has `sortField` and `sortAscending`. Fields: `deadline`, `start`, `title`, `createdAt`, `modifiedAt`, `closedAt`, `status`. (`manualPosition` is meaningless across mixed parents — hidden for smart filters.) Ties broken by `createdAt asc, id asc`.

### Performance

Personal-scale datasets (~thousands). Direct `NSFetchedResultsController` is fine. Compound index on `(task, kind)` for `JournalEntry`. FTS5 deferred until justified.

### CLI surface

```
lillist filter --any tag:Work,Home --status started,todo --deadline-before +3d --sort deadline
lillist filter --saved "End of Week Review"
lillist filter --saved "End of Week Review" --json
```

Same `PredicateGroup` value; same evaluator.

### Authoring UI

Vertical stack of rule rows: `[Field popup] [Operator popup] [Value editor] [remove]`. Top toggle: "Match: [All ▾] / [Any ▾]". Right-side live preview.

---

## 6. The CLI

### Identity & distribution

`lillist`, macOS only in v1. Installed from the macOS app (with consent) to `/usr/local/bin/` or `~/.local/bin/`; also available via Homebrew tap.

### Data access

Opens the same Core Data store as the macOS app via the app group container. iCloud account inherited from app configuration. If no app installed / never run: exit with a friendly install pointer.

### Concurrency

Core Data + SQLite WAL handles concurrent readers and serialized writers. CLI mutations flow through `NSPersistentCloudKitContainer` identically to app mutations.

### Argument parser

`swift-argument-parser`. Commands grouped as nested subcommands, each handled by `LillistCore.CLIBridge`.

### Top-level commands

```
lillist add <title> [--start <when>] [--deadline <when>] [--tag <name>...] [--notes <text>]
                    [--parent <task-id|fuzzy>] [--status <status>]
lillist ls [--saved <filter-name>] [--any|--all] [--tag ...] [--status ...]
           [--deadline-before <when>] [--deadline-after <when>] [--start-before <when>]
           [--has-attachments] [--pinned] [--include-trash]
           [--sort <field>] [--json|--ndjson|--tsv]
lillist show <task-id|fuzzy>
lillist edit <task-id|fuzzy> [...same flags as add...]
lillist status <task-id|fuzzy> <todo|started|blocked|closed> [--note <text>]
lillist note <task-id|fuzzy> <body>
lillist attach <task-id|fuzzy> <path>...
lillist link <task-id|fuzzy> <url>
lillist tag <task-id|fuzzy> [+#tag]... [-#tag]...
lillist pin <task-id|fuzzy>
lillist unpin <task-id|fuzzy>
lillist move <task-id|fuzzy> <new-parent-id|fuzzy|--root>
lillist delete <task-id|fuzzy>            # soft delete
lillist restore <task-id|fuzzy>
lillist purge <task-id|fuzzy>             # hard delete
lillist nudge <task-id|fuzzy> --at <when>
lillist tags [ls | add | rename | move | delete | tint]
lillist filters [ls | show | run | save | delete]
lillist search <query> [--scope <task-id>] [--json]
lillist export <dir>
lillist version
lillist completion <bash|zsh|fish>
lillist watch [--saved <filter>]
lillist count [...filter flags...]
lillist eval <predicate-expression>
lillist report-crash
```

### Fuzzy task resolution

- Case-insensitive, diacritic-insensitive substring match on `title` via `localizedStandardContains`.
- Default scope: non-trashed, non-closed. `--include-closed` extends.
- UUID-prefix routing: tokens matching `^[0-9a-f]{4,}$` resolve as UUID prefixes.
- Exact title match (case-insensitive) wins over substring.
- Multiple matches → exit 4, list candidates, do not act.
- Read-only verbs pick best match silently with stderr note.
- Destructive verbs (`delete`, `purge`, `move`, `status …closed`, `restore`): require UUID or exact match. No partial-match action.
- `--exact "<title>"` for scripts.
- `--scope <task-id>` restricts to descendants.

### Date/time parsing

Same relative DSL as smart filters, plus ISO-8601, plus common natural-language phrases. Time-of-day optional; absence sets `*HasTime = false`.

### Output formats

- Default: human-readable pretty tree / indented detail; ANSI color when stdout is a TTY.
- `--json`: single JSON document.
- `--ndjson`: one JSON object per line.
- `--tsv`: tab-separated with header.

stdout for data; stderr for diagnostics.

### Exit codes

- `0` success
- `1` generic error
- `2` usage error
- `3` not found
- `4` ambiguous match
- `5` store unavailable

### Stdin batch mode

Commands accept `-` for stdin (one identifier per line). Destructive verbs **reject** non-UUID stdin inputs unless `--allow-fuzzy-from-stdin` is set; fail fast on first ambiguous title rather than partial-apply.

### Scriptability primitives

- `lillist watch` — long-running, emits NDJSON events on matching changes via `NSFetchedResultsController`.
- `lillist count` — single integer; for shell prompts.
- `lillist eval` — evaluate predicate against task / stdin set without saving.

### Configuration

`~/.config/lillist/config.toml` — default output format, sort, time zone. Per-machine, not synced.

### App Intents alignment

Shortcuts mirrors the CLI verb set. Same `LillistCore.CLIBridge` underneath.

---

## 7. UI Structure

Three columns on macOS/iPadOS, two-tier on iOS. SwiftUI throughout, `NavigationSplitView` as backbone.

> **Visual design:** structure and behavior are specced here; the look
> (tokens, color semantics, elevation, typography, density, component
> treatments) is owned by the Rainbow Logic design system —
> `2026-06-12-rainbow-logic-design-system.md`.

### macOS / iPadOS

**Sidebar (left):**
1. **Pinned** — pinned tasks and pinned smart filters, intermixed, user-ordered. Icon differentiates kind.
2. **Tags** — nested tag tree. Drag to reorder/reparent. Right-click for color/rename/delete.
3. **Filters** — non-pinned saved smart filters.
4. **Trash** — fixed entry with count badge.

The sidebar is navigation, not the task tree. Tasks-as-tree are content (middle column).

**Middle column (task list):**
- Header with source name, counts, sort/group control.
- Outline view when source has children; flat list with breadcrumb when results span multiple parents (e.g. smart filter).
- Left-side status indicator (`◯ todo`, `◐ started`, `◌ blocked`, `✓ closed`). Click cycles; long-press / right-click opens menu including "schedule follow-up" for Blocked.
- Inline tag chips.
- Drag handle, location-sensitive DnD: between two tasks = reorder, onto a task = re-parent.
- Inline create: Return = sibling, Tab = indent, Shift-Tab = outdent.

**Right column (detail):**
- Title + status pill + tags + start/deadline.
- Notes (Markdown editor, live preview toggle).
- Subtasks: compact outline with inline create.
- Journal & Attachments: single stream with composer at bottom; accepts text, dragged files, pasted URLs (auto-unfurl). Each entry has timestamp + edit/delete (system entries reject edit). "Attachments" tab filter at the top of the stream.

**Recurrence editor.** The task detail surface includes a recurrence
editor (Plan 11) that lets the user toggle "Doesn't repeat" / "Repeats…"
and configure either a calendar rule (frequency, byDay, byMonthDay,
bySetPos, count, until) or an after-completion rule (interval in
seconds, presets for common windows). The "this only" / "all future"
fork affordances remain out of v1 UI scope; CLI and App Intents access
them.

### iOS

Two-tier with sheets. Tab bar: **Today / All / Filters / Search**.
- **Today** is a built-in smart filter (start ≤ today OR deadline ≤ today, non-closed, non-trashed). Default landing view.
- **All** opens the tag-tree drawer; tag → task list.
- Task detail pushes onto the stack. Journal/notes as tabs within detail.
- Quick capture: floating "+" button, Lock Screen Shortcut, share-sheet target.

### Cross-platform conventions

**Keyboard shortcuts (macOS / iPadOS hardware):**
- ⌘N new task, ⌘⇧N new sibling
- Tab / Shift-Tab indent/outdent
- Space toggle status to/from started
- ⌘D mark closed
- ⌘. mark blocked + reveal follow-up form
- ⌘F search in view, ⌘⇧F search everywhere
- ⌘1/2/3 focus sidebar / list / detail

**Global hotkey (macOS):** ⌃⌥Space opens Quick Capture — borderless window, single text field, `#` for tag autocomplete, `^` for date phrases, Return to save, Esc to dismiss. Configurable.

**Dark mode:** full support; tag tint colors slightly desaturated in dark mode.

**Accessibility:** Dynamic Type, VoiceOver labels on all interactive elements, explicit a11y labels for status indicators and tag chips.

### Quick capture surfaces

- macOS: global hotkey (default ⌃⌥Space)
- iOS: share-sheet extension + Shortcuts action + floating "+"
- iPadOS: same as iOS + ⌘N on hardware keyboard
- CLI: `lillist add`

No widgets in v1.

### State persistence

Sidebar selection, expansion state, per-source sort: stored locally per-device, **not** synced. The principle: *what* you have is synced; *how you're looking at it right now* is not.

### Empty states

Tailored per surface. Empty smart filter results explain the predicate that produced zero matches and link to the editor.

### Onboarding

Single-screen intro: iCloud requirement, notification permission, global hotkey. Skip option. Default smart filters double as a guided tour by example.

### Pre-installed defaults (deletable)

Smart filters: **Today**, **This Week**, **No Tags**, **Recently Closed** (last 7 days), **Stale** (`createdAt == modifiedAt` and older than 3 days).
Tags: none. Blank tag tree — no prescribed workflow.

---

## 8. Error Handling and Failure Modes

### Error taxonomy

```swift
enum LillistError: Error {
    case storeUnavailable(reason)
    case iCloudUnavailable(reason)
    case syncFailure(underlying)
    case validationFailed([Issue])
    case notFound
    case ambiguous([CandidateID])
    case quotaExceeded(resource)
    case attachmentTooLarge(byteSize)
    case attachmentFetchFailed(url)
    case migrationRequired
    case migrationFailed(underlying)
}
```

UI maps to user-facing strings; CLI maps to exit codes + stderr messages.

### iCloud account states

- **Available:** normal.
- **No account:** full-screen blocker explaining iCloud is required, with Settings deep-link.
- **Restricted** (parental controls, MDM): read-only with banner.
- **Account changed:** on next launch, prompt to confirm. On confirm, local store moved to quarantine path; fresh store created. Quarantine preserved 30 days then auto-cleaned.

### Sync indicator

Sidebar indicator:
- Green dot: synced < 1 min ago.
- Spinner: in progress.
- Yellow dot: 1–10 min ago (normal idle).
- Red dot: persistent error; popover with details, last successful sync, "Try again."

Transient errors retried with exponential backoff silently.

### Quota exceeded

- Attachment row → "upload failed: storage full" with retry.
- Journal entry persists locally.
- One-time alert pointing at iCloud storage management.

### Validation rules

- Cyclic parent → reject.
- Tag rename collision → auto-suffix " (2)", warn in CLI / show inline notice in UI.
- Smart filter with zero predicates: allowed (matches all non-trashed); UI confirmation.
- Attachment size: soft cap at 50 MB (confirmation), hard refusal above 500 MB.

### Recurrence edge cases

- DST: wall-clock time preserved across transitions via `DateComponents`-based triggers.
- `byMonthDay = 31` in shorter months: skip month, do not spawn on the 30th.
- Re-opening a closed instance: spawn already happened; not undone. Re-open recorded as status change.
- Series `until` mid-flight: existing instances unaffected; no further spawns.

### Attachment & link preview robustness

- Link previews: 10s timeout, 5 MB cap, HTML-only parsing.
- Images preserved as-is including EXIF (callout for future strip-EXIF preference).
- Failed previews: raw URL shown with retry.

### Sync conflict-of-deletes

Concurrent soft-delete + edit converges to "in Trash with edits intact." Restore brings back the edited version.

### Auto-purge job

Runs on foreground + daily background timer:
- Hard-deletes tasks with `deletedAt` older than `trashRetentionDays`.
- Cascades to children.
- Removes `CKAsset` attachments.
- Skips when iCloud unavailable (avoid divergent device-local purges).

### Notification delivery edge cases

- Closed/deleted task between scheduling and firing: scheduler reconciles on every relevant mutation; foreground `willPresent` handler also suppresses.
- Tapping a notification whose task has been closed: opens a sensible "this task was closed" detail rather than crashing.

### Data corruption recovery

Core Data store fails to open → recovery screen offering:
- "Reset local store and re-sync from iCloud" (lossless if iCloud has it).
- "Export raw store for diagnosis" (zip to Desktop).

No silent reset, ever.

### Crash detection and opt-in reporting

**Canary mechanism.** A canary file at `~/Library/Application Support/Lillist/launch.canary` (and iOS app group equivalent). On clean launch we write `{pid, startedAt, buildVersion}`. On clean termination we delete it. On launch, if it exists, treat as crash; read for context, delete, write fresh.

Caveats accepted: OS-killed-for-memory, force-quit, and power loss look like crashes. Wording ("Lillist quit unexpectedly") is honest either way. Crashes during very early launch are not detected (rare; OS crash dialog still covers them).

**Post-crash sheet.** On the next launch (non-blocking), after normal startup:

> **Lillist quit unexpectedly last time.**
>
> Help me make it more reliable by sending a quick report. Totally optional.
>
> **What were you doing?** (free-form text, optional)
> [ textarea ]
>
> **What to include**
> ☑ Recent app logs *(last 5 min, ~50 KB; reviewable below)*
> ☑ Last action breadcrumbs *(no titles or content, just verbs and counts)*
>
> [ View what will be sent ] [ Don't send ] [ Send report ]
>
> *Reports go directly to Mikey (mikeyward@gmail.com). No third-party telemetry.*

Both checkboxes default **on**; clear opt-out via "Don't send" or unchecking.

**Report contents.**
- Always (if user sends): build version, OS version, device model, canary record, user description.
- If logs checked: `OSLog` entries from crashed PID's lifetime within last 5 min, redacted to strip task titles, notes, journal bodies, tag names, file paths under user dirs.
- If breadcrumbs checked: in-memory ring buffer of last 200 actions as `{action, at, success}` — no titles, no IDs.
- Never: task content, attachment contents, iCloud account identifier.

**Delivery.** `mailto:` on macOS / `MFMailComposeViewController` on iOS. No server, no API key, no SDK. User sends the email themselves. "Save as file…" alternate produces a `.lillistcrash` bundle for manual delivery.

**CLI alignment.** CLI follows the same canary protocol. After unclean CLI exit and stdout is a TTY: one-line notice. `lillist report-crash` runs the flow non-interactively (prints redacted payload, reads description from stdin, opens `mailto:` via `open`).

### Telemetry stance

**No remote telemetry in v1.** Logs are local via `OSLog`. Crash reports are user-mediated and opt-in per crash.

---

## 9. Testing Strategy

Model package is where bugs that matter live; UI is where bugs that annoy live. Budget weighted accordingly.

### Frameworks

Swift Testing for new tests in `LillistCore`. XCTest for UI snapshot suites until Swift Testing reaches parity. No third-party assertion libraries.

### `LillistCore` — ~70% of test effort

1. **Model invariants and validation.**
   - Cycle prevention on re-parent.
   - Cascade-delete including journal entries and attachments.
   - `closedAt` automation on status transitions.
   - Tag uniqueness-among-siblings and rename collision.
   - Implicit `inTrash is false` predicate.

2. **Predicate engine.**
   - Shared fixture set: ~30 `(PredicateGroup, [Task]) → expected` cases covering every field × operator + tricky compositions.
   - Both evaluation paths (NSPredicate + pure Swift) run every fixture; divergence fails.
   - Property-based tests for the relative date DSL.

3. **Recurrence math.**
   - Every `freq`/`byDay`/`byMonthDay`/`bySetPos` combination.
   - DST fixtures.
   - `byMonthDay = 31` skip-month.
   - After-completion spawn timing including re-opens.
   - Series fork from non-seed instance.
   - `until` mid-flight.

4. **Sync merge scenarios.** Two in-memory `NSPersistentCloudKitContainer` stores:
   - Concurrent field edits converge.
   - Soft-delete + concurrent edit → "in trash, edited."
   - Reorder on two devices, deterministic-given-fixture result.
   - Series fork during sync converges to same graph on both.

5. **CLI bridge.** Every `CLIBridge` command:
   - Parses representative argument string.
   - Executes against in-memory store.
   - Asserts output payload (JSON-comparison for `--json`; golden-string for human-readable, normalized).
   - Asserts exit code.

### App targets — ~20% of test effort

- **Snapshot tests** (e.g. `pointfreeco/swift-snapshot-testing`) for steady-state views, dark/light variants. Snapshot diffs gate PRs.
- **Integration tests** for highest-stakes interactions: location-sensitive DnD, inline create with Tab/Shift-Tab nesting, quick-capture flow.

### Extensions and App Intents

App Intents tested via direct invocation of `perform()` against in-memory store. Share Extension verified by hand at release time.

### Notifications

- `NotificationScheduler` tested against stubbed `UNUserNotificationCenter` (protocol-wrapped).
- End-to-end delivery verified manually on real devices at release time.

### Performance budgets (assertion-tested)

- Cold launch macOS: < 1s to usable UI with 5,000 tasks.
- Smart filter evaluation: < 100ms against 10,000 tasks.
- Tree reparent on 100 descendants: < 50ms.

### CI

Xcode Cloud. On every push:
- Build all targets for all platforms.
- Run `LillistCore` tests on macOS and iOS Simulator.
- Run snapshot tests.
- Lint pass: `swiftformat --lint` + custom check that all `Predicate` field cases have NSPredicate + Swift-evaluator coverage in the fixture set.

### Test Engineer subagent review

Every meaningful PR involving `LillistCore` (model, rules, recurrence, CLI bridge) requires a Test Engineer subagent review pass before merge — assessing not just coverage numbers but:
- User behaviors covered.
- Value-vs-validation balance (are we testing real outcomes or just shapes?).
- Edge case taxonomy completeness.
- Mutation-test-style rigor ("would this test catch a real bug?").

Captured as an explicit workflow step in the implementation plan.

### Coverage targets (aspirational, non-gating)

- `LillistCore.Model` / `Rules` / `Recurrence` / `CLIBridge`: 90%+.
- `LillistCore.Persistence` / `Sync`: 70%+.
- App targets: untracked. Snapshots catch what counts.

### Explicitly not tested in v1

- Real CloudKit (manual at release across Mac + iPhone + iPad).
- Non-English locales (relying on `localizedStandardContains` and system formatters; add fixtures as bugs surface).

---

## 10. Out of v1 (Intentionally)

- Multi-user / shared tasks / collaboration.
- Linux/Windows CLI.
- Apple Watch app.
- Widgets / Lock Screen widgets.
- Local-only / sync-less mode (transient offline is supported; account-less is not).
- Import from other tools (Things / OmniFocus / TaskPaper / Reminders).
- Attachment text extraction (OCR for search).
- Nested smart filter groups in UI (data model supports).
- Custom statuses.
- Numeric progress percentage.
- Per-tag manual ordering for tasks.
- Custom snooze durations.
- Multi-parent tags.
- Time tracking / pomodoro / focus timers.
- Remote telemetry / analytics.
- Calendar / Reminders bidirectional sync (EventKit).
- Localization beyond English.
- Markdown / Pandoc / API export formats.

### Likely v2 roadmap (informational)

- Attachment text extraction and indexing.
- Custom snooze options.
- Widgets.
- TaskPaper import.
- Nested smart filter groups in UI.
- Apple Watch quick capture.
- Localization.

---

## Appendix A — Section Summary

1. Platforms & build topology (macOS / iOS / iPadOS + CLI; Swift workspace with `LillistCore` shared package).
2. Data model (pure-nesting Tasks; Tags with single-parent hierarchy; JournalEntries; Attachments; Series; SmartFilters; NotificationSpecs).
3. Sync, storage, migrations (`NSPersistentCloudKitContainer` with field-level merge; custom zone; soft-delete + Trash; lazy attachment download).
4. Notifications, snooze, nudges (four layers, cross-device de-dup via `lastFiredAt`, extensible snooze registry, Blocked-state follow-up affordance).
5. Smart filters & rule engine (flat AND/OR in v1, recursive data model, dual evaluation paths with fixture-parity tests, relative date DSL).
6. CLI (`lillist` with fuzzy resolution, stdin batch mode with destructive-verb guards, NDJSON/JSON/TSV output, `lillist watch`/`count`/`eval` primitives, Shortcuts parity).
7. UI structure (three-column macOS/iPadOS, two-tier iOS, sidebar = Pinned/Tags/Filters/Trash, location-sensitive DnD, keyboard-first nesting).
8. Error handling (typed error taxonomy, iCloud state handling, canary-based opt-in crash reporting with default-on checkboxes).
9. Testing strategy (heavy `LillistCore` suite with predicate-engine fixture parity, snapshot tests for UI, performance budgets, Xcode Cloud CI, Test Engineer subagent review of test quality).
10. Out of v1 (multi-user, watch, widgets, OCR, custom statuses, EventKit, localization).
