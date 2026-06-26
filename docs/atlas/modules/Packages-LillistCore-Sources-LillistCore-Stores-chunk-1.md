---
module: "Packages/LillistCore/Sources/LillistCore/Stores (chunk 1)"
summary: "Six secondary stores (attachment/journal/prefs/series/smart-filter/tag) + TaskStore follow-up and tag-query extensions"
read_when: "Touching attachments, journal, tags, or prefs"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift
    blob: af70d4e18ae0d9635865a60d0738a7fd7957293c
  - path: Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift
    blob: 4deba503a11896230e9a21dc091cd75dd9b7726e
  - path: Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift
    blob: bd5a5268cb8cc339f73a5e85aa8d5ff8c366850f
  - path: Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift
    blob: ee2963186428c389bb77f393cca23f1ebad56218
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift"
    blob: 3710bb423e779c73223094f2df20aff7135cb8e1
  - path: Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift
    blob: 4bdfc4c6eab859c84adbecad3c19c15e8315fb22
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TagStore+FindOrCreate.swift"
    blob: fbc084e94d18ae6747564cb8e4b0c32399efc2d0
  - path: Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift
    blob: 2fc1dc6f0c94a92e9db32d06599663b47d9a5ea6
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift"
    blob: b3ea7804bc55e54eac0dd1c3d86884defd7925a1
  - path: "Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift"
    blob: f86757470cea6dcb8c5994fb9bc741ebffd033f0
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-ManagedObjects, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistCore-Sources-LillistCore-Rules, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistCore-Sources-LillistCore-misc, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/Stores (chunk 1)

## Purpose

This chunk holds the secondary-entity stores — AttachmentStore, JournalStore, PreferencesStore, SeriesStore, SmartFilterStore, and TagStore — plus TaskStore extensions for follow-up creation and tag/pinned queries. Together they are the only sanctioned path to reading or writing preferences, tags, smart filters, journal entries, attachments, and recurrence series, all exposed as value-type DTOs with no NSManagedObject escapes. If the chunk vanished, the entire non-task data layer and the smart-filter evaluation engine would disappear.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AttachmentRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:24` | Sendable, Equatable DTO for one attachment row; all fields are value types and no NSManagedObject reference escapes. |
| `AttachmentStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:4` | The sole async gateway for attachment CRUD; enforces a 500 MB hard size limit and returns only AttachmentRecord, never managed objects. |
| `DefaultSmartFilters` | enum | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:27` | Namespace for the five built-in filter specs (Today, This Week, No Tags, Recently Closed, Stale); not user-facing, drives installDefaultsIfNeeded. |
| `JournalRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:21` | Sendable, Equatable DTO for a journal entry; kind field distinguishes system-generated events from user notes. |
| `JournalStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:4` | The sole async gateway for task journal entries; enforces that system entry kinds (non-user-editable) cannot be edited or deleted. |
| `LinkPreviewPayload` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:37` | Codable, Sendable payload stored as JSON in linkPreviewJSON; carries URL, optional title/description, and fetch timestamp. |
| `PreferencesStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:4` | Thread-safe singleton store for app preferences; broadcasts Prefs snapshots to all prefsStream subscribers including across CloudKit remote-change notifications. |
| `Prefs` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:51` | Sendable, Equatable value-type snapshot of all app preferences; the only type callers see when reading or mutating preferences. |
| `SeriesRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:13` | Sendable, Equatable DTO for a recurrence series; carries rule, seed task ID, and next-occurrence date. |
| `SeriesStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:4` | The sole async gateway for recurrence series CRUD and fork operations; owns nextOccurrenceAfter computation via RecurrenceExpander. |
| `SmartFilterDraft` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:65` | Mutable projection passed to the update closure; exposes only the writeable fields callers may change. |
| `SmartFilterRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:27` | Sendable, Equatable DTO for a saved smart filter; includes position, isPinned, and the decoded PredicateGroup. |
| `SmartFilterStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:3` | Extension on SmartFilterStore that adds installDefaultsIfNeeded; keeps bootstrap logic separate from the main class body. |
| `SmartFilterStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:7` | The sole async gateway for smart filter CRUD, ordering, evaluation, and predicate JSON codec; also executes predicate queries against tasks. |
| `SmartFilterStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:291` | Extension adding fetch(byName:) and delete(byName:) name-keyed lookup; throws notFound or ambiguous as appropriate. |
| `SmartFilterStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:309` | Extension adding setPinned and reorder with heal-then-recheck logic for tied/inverted fractional-position anchors. |
| `SmartFilterStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:432` | Extension adding evaluate (saved and ad-hoc), count, sortDescriptors, and record(from: LillistTask) — the filter-execution and task-projection surface. |
| `Spec` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:28` | Package-internal struct bundling the static definition (name, predicate group, tint, sort) for one default filter; consumed only by installDefaultsIfNeeded. |
| `TagRecord` | struct | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:21` | Sendable, Equatable DTO for a tag row; includes hierarchical parentID and fractional position. |
| `TagStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore+FindOrCreate.swift:4` | Extension on TagStore adding the atomic findOrCreate operation for Quick Capture tag resolution. |
| `TagStore` | class | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:4` | The sole async gateway for hierarchical tag CRUD; enforces cycle-free reparenting and name uniqueness within a sibling group. |
| `TaskStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift:4` | Extension on TaskStore adding the scheduleFollowUp operation; keeps follow-up creation logic separate from the main class. |
| `TaskStore` | extension | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:4` | Extension on TaskStore adding pinned, tasks(forTag:), and breadcrumbs query methods. |
| `addFile` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:62` | Stores arbitrary binary data with an explicit UTI; enforces hardSizeLimit before inserting and returns the new attachment UUID. |
| `addImage` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:47` | Stores image data tagged public.image; enforces hardSizeLimit before inserting and returns the new attachment UUID. |
| `addLinkPreview` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:77` | Creates a .linkPreview attachment with OG metadata encoded to JSON; thumbnailData and faviconData are accepted but currently ignored. |
| `appendNote` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:34` | Creates a user-authored .note journal entry on the given task; returns the new entry UUID. |
| `attachments` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:177` | Returns all attachments for a task sorted by createdAt ascending; result is empty if the task has no attachments. |
| `breadcrumbs` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:74` | For a batch of task IDs, returns the reversed ancestor-title chain for each; root tasks map to empty arrays, missing tasks are omitted. |
| `children` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:64` | Returns the immediate child tags of the given parent (nil = root), sorted by fractional position ascending. |
| `computeNextOccurrence` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:138` | Static helper dispatching to RecurrenceExpander; returns the next fire date for a calendar rule or an after-completion rule, nil when no future occurrence exists. |
| `count` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:497` | Counts matching tasks for a saved filter without materializing records; used for badge counts. |
| `create` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:23` | Creates a Series rooted at a seed task, computes the initial nextOccurrenceAfter, and links the seed task into the series. |
| `create` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:76` | Creates a SmartFilter with the predicate group encoded as JSON and a fractional position after the last existing row. |
| `create` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:32` | Creates a new tag with a name unique within the sibling group; suffix-disambiguates collisions via uniqueNameUnder. |
| `decode` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:281` | Parses a JSON string into a PredicateGroup; throws validationFailed on malformed UTF-8 or invalid JSON. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:188` | Hard-deletes the attachment row by UUID; throws LillistError.notFound if absent. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:91` | Hard-deletes the journal entry; throws validationFailed if the entry is a non-user-editable system kind. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:80` | Hard-deletes the Series row; linked task instances retain the series relationship until reconciled by RecurrenceSpawner. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:185` | Hard-deletes the SmartFilter row by UUID; throws LillistError.notFound if absent. |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:303` | Deletes the filter with this exact name by delegating to fetch(byName:) then delete(id:). |
| `delete` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:124` | Hard-deletes the tag row; subtree cascade behavior is defined by the Core Data model relationship. |
| `downloadData` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:165` | Triggers CKAsset materialization by touching .data; throws attachmentFetchFailed when bytes are absent (link-preview rows or pending CloudKit downloads). |
| `editNote` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:75` | Replaces the body of a user note and stamps editedAt; throws validationFailed for system entry kinds. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:274` | Serializes a PredicateGroup to sorted-keys JSON string; the inverse of decode. |
| `entries` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:64` | Returns all journal entries for a task sorted by createdAt ascending; includes system entries. |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:437` | Executes a saved filter's predicate against LillistTask rows sorted by the filter's stored sort field; excludes trash by default. |
| `evaluate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:469` | Executes an ad-hoc PredicateGroup against tasks with optional archived-include, pagination (limit/offset), and configurable sort. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:146` | Returns the AttachmentRecord for the given UUID; throws LillistError.notFound if absent. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:57` | Returns the JournalRecord for the given UUID; throws LillistError.notFound if absent. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:43` | Returns the SeriesRecord for the given UUID; throws LillistError.notFound if absent. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:105` | Returns the SmartFilterRecord for the given UUID; throws LillistError.notFound if absent. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:294` | Returns the SmartFilterRecord by exact name; throws notFound if no match, ambiguous if multiple rows share the name. |
| `fetch` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:57` | Returns the TagRecord for the given UUID; throws LillistError.notFound if absent. |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:128` | Internal lookup of a Series managed object by UUID; exposed as internal (not private) for use by RecurrenceSpawner. |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:195` | Internal lookup of a SmartFilter managed object by UUID; used by all write paths within SmartFilterStore. |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:153` | Internal lookup of a Tag managed object by UUID; used by extensions and sibling-scope queries sharing the context. |
| `findOrCreate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore+FindOrCreate.swift:14` | Atomically looks up or creates a tag by case-insensitive name under the given parent; the read and optional insert run in one context.perform block. |
| `forkFutureFromInstance` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:94` | Creates a new Series rooted at a non-seed instance, detaching it from the old series for edit-all-future semantics; throws if called on the seed task. |
| `installDefaultsIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore+Defaults.swift:11` | Idempotently seeds the five default smart filters; skips any filter whose name already exists, preserving user edits. |
| `instances` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:50` | Returns the UUIDs of all LillistTask instances belonging to the given series. |
| `list` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:58` | Returns all series records sorted by nextOccurrenceAfter ascending. |
| `list` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:142` | Returns all SmartFilterRecords sorted by fractional position using SiblingOrder.precedes; position ties are broken by id lexical order. |
| `nextPosition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:205` | Computes a fractional position value after the current last filter row; must be called inside a context.perform block. |
| `nextPosition` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:161` | Computes a fractional position after the last sibling under the given parent; must be called inside a context.perform block. |
| `normalizeIfDegenerate` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:117` | Compacts all SmartFilter positions if any adjacent pair is not strictly increasing; idempotent and called at the filters-list load seam. |
| `normalizeSingletons` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:231` | Idempotent one-time-per-launch pass that collapses multiple AppPreferences rows to a single canonical row with singletonID; safe to call on every bootstrap. |
| `pinned` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:10` | Returns all non-deleted pinned tasks sorted by position; excludes soft-deleted rows. |
| `read` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:74` | Returns a Prefs snapshot from the AppPreferences singleton row; creates the row with defaults if no row exists yet. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:261` | Static projection from Attachment managed object to AttachmentRecord; the canonical DTO mapper used by all public read paths. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:122` | Static projection from JournalEntry managed object to JournalRecord; the canonical DTO mapper for all read paths. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:152` | Internal projection from Series managed object to SeriesRecord; exposed as internal for RecurrenceSpawner. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:251` | Projects a SmartFilter managed object to SmartFilterRecord, decoding predicateGroupJSON; throws if JSON is malformed. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:529` | Projects a LillistTask managed object to TaskStore.TaskRecord; used by evaluate and count to return task data without a TaskStore instance. |
| `rename` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:80` | Renames a tag; enforces uniqueness within the sibling group by suffix-disambiguating collisions. |
| `reorder` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:334` | Places a filter at a fractional position between after/before anchors; detects ties/inversions, heals by recompacting, then retries before throwing. |
| `reparent` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:99` | Moves a tag to a new parent; guards against cycles via wouldCreateCycle, assigns a new fractional position, and suffix-disambiguates the name under the new parent. |
| `rowCount` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:178` | Returns the count of AppPreferences rows; intended for tests to assert the singleton invariant. |
| `scheduleFollowUp` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+FollowUp.swift:16` | Creates a sibling follow-up task with a deadline, appends a .createdFollowUp journal entry on the blocked task, and reconciles notifications. |
| `setCrashPromptsEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:173` | Convenience wrapper over update(_:) that toggles crashPromptsEnabled; persists and broadcasts the change. |
| `setPinned` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:310` | Toggles the isPinned flag on a SmartFilter row and stamps modifiedAt. |
| `setTintColor` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:143` | Stores a hex color string on the tag row; no format validation is performed (caller's responsibility). |
| `sortDescriptors` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:510` | Returns NSSortDescriptors for the given SortField and direction, with createdAt and id as tiebreakers. |
| `tasks` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore+Queries.swift:28` | Returns non-trash tasks tagged with the given tag or any descendant, de-duplicated, sorted by the given SortField. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:95` | Applies a mutation closure to the current Prefs, persists the result, and broadcasts the new snapshot to all prefsStream subscribers. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SeriesStore.swift:68` | Replaces the recurrence rule and recomputes nextOccurrenceAfter from the seed task's start date. |
| `update` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:160` | Applies a mutation closure to a SmartFilterDraft, validates the name, re-encodes the predicate group, and persists. |
| `updateLinkPreview` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:109` | Merges new OG metadata into the stored JSON payload for a link-preview attachment; nil metadata fields preserve the existing values. |
| `validateName` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:243` | Throws validationFailed if the name is blank after whitespace trimming. |
| `validateName` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:198` | Throws validationFailed if the name is blank after whitespace trimming. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `broadcast` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:162` | Delivers Prefs snapshots to all registered continuations; every update(_:) call and every CloudKit remote-change notification routes through this single multicast point (PreferencesStore.swift:162-169). |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:245` | Single lookup bottleneck for all AttachmentStore read/write/delete paths; enforces LillistError.notFound as the only exit for a missing row (AttachmentStore.swift:245-251). |
| `fetchManagedObject` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:106` | Single lookup bottleneck for all JournalStore read/write/delete paths; enforces LillistError.notFound as the only exit for a missing row (JournalStore.swift:106-112). |
| `fetchTask` | func | `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift:253` | Validates the parent task exists before any attachment is inserted via insertAttachment; prevents orphaned attachment rows (AttachmentStore.swift:253-259). |
| `fetchTask` | func | `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift:114` | Validates the parent task exists before a new journal entry is created by appendNote; prevents orphaned journal entries (JournalStore.swift:114-120). |
| `recompactSiblings` | func | `Packages/LillistCore/Sources/LillistCore/Stores/SmartFilterStore.swift:226` | Re-spaces all SmartFilter rows to even 1.0 gaps before position computation; must run inside the same context.perform block as the target update to ensure atomicity (SmartFilterStore.swift:226-241). |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:206` | Single NSManagedObject→TagRecord conversion bridge that enforces the 'no Tag escapes LillistCore' invariant. Every public read path that returns a value type flows through it: `fetch` (TagStore.swift:60) and `children` via `.map(record(from:))` (TagStore.swift:74). Centralises nil-coalescing of optional Core Data fields (`id`, `name`) and parentID unwrapping so callers receive a fully-typed, non-optional DTO. |
| `register` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:150` | Adds a continuation to the subscriber registry under NSLock; called by prefsStream for every new subscriber — without it multicast delivery is impossible (PreferencesStore.swift:150-154). |
| `unregister` | func | `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift:156` | Removes the continuation on stream termination; prevents memory leaks and dead yield calls on closed streams (PreferencesStore.swift:156-160). |
| `wouldCreateCycle` | func | `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift:187` | Guards the tag hierarchy against parent cycles by walking ancestor chain before reparent commits; without it infinite traversal loops are possible (TagStore.swift:187-196). |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticEvent (emits)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.Spec -> Packages-LillistCore-Sources-LillistCore-Rules.Leaf (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.Spec -> Packages-LillistCore-Sources-LillistCore-Rules.PredicateGroup (owns)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.addLinkPreview -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.computeNextOccurrence -> Packages-LillistCore-Sources-LillistCore-Recurrence.nextAfterCompletion (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.computeNextOccurrence -> Packages-LillistCore-Sources-LillistCore-Recurrence.nextOccurrences (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.count -> Packages-LillistCore-Sources-LillistCore-Rules.compile (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.emitReorderDiag -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.encode -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.evaluate -> Packages-LillistCore-Sources-LillistCore-Rules.compile (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.list -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.nextPosition -> Packages-LillistCore-Sources-LillistCore-Ordering.position (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Diagnostics.zip (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.normalizeIfDegenerate -> Packages-LillistCore-Sources-LillistCore-Ordering.recompact (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Diagnostics.zip (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Ordering.precedes (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.recompactSiblings -> Packages-LillistCore-Sources-LillistCore-Ordering.recompact (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.record -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskRecord (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.anchorsAreOutOfOrder (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.needsCompaction (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.reorder -> Packages-LillistCore-Sources-LillistCore-Ordering.position (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.scheduleFollowUp -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.stampCurrentSchemaVersion (writes)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.scheduleFollowUp -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.validateTitle (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.uniqueNameUnder -> Packages-LillistCore-Sources-LillistCore-misc.uniqueName (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.updateLinkPreview -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`

## Type notes

All store classes are `public final class: @unchecked Sendable`; thread safety is each store's own responsibility. Every mutation runs inside `context.perform` on the viewContext, serializing on Core Data's context queue.

PreferencesStore maintains a live-multicast `AsyncStream<Prefs>` via a `[UUID: AsyncStream<Prefs>.Continuation]` dictionary guarded by `NSLock` (PreferencesStore.swift:19-21). It also observes `NSPersistentStoreRemoteChange` so CloudKit pulls trigger a re-read and broadcast to all subscribers (PreferencesStore.swift:29-42). `singletonID` (PreferencesStore.swift:14) is a fixed UUID literal and must never be changed — existing CloudKit stores converge on it for cross-device preferences.

SmartFilterStore carries an optional `diagnosticLog: DiagnosticSink?` (SmartFilterStore.swift:14) used only by `reorder`; all stores with optional sinks treat nil as a no-op. `recompactSiblings` must execute inside the same `context.perform` block as the target position update — the comment at SmartFilterStore.swift:213-221 explains the atomicity requirement.

TagStore declares `let persistence` and `var context` as internal (not private) so the `+FindOrCreate` extension can access `persistence` directly (TagStore.swift:5-6).

SeriesStore exposes `fetchManagedObject` and `record` as internal (not private) so RecurrenceSpawner can call them without going through the async public API (SeriesStore.swift:128, 152).

## External deps

- CoreData — imported
- Foundation — imported

## Gotchas

PreferencesStore.singletonID (PreferencesStore.swift:14) is a fixed UUID literal — the comment explains that prior random-UUID approach caused CloudKit to mint two distinct singleton rows per device, making preferences flip-flop. It must never be regenerated.

SmartFilterStore.record#2 (SmartFilterStore.swift:529-550) duplicates the LillistTask → TaskStore.TaskRecord field projection that TaskStore.record(from:) also implements. Any new LillistTask field must be added to both.

AttachmentStore.insertAttachment (AttachmentStore.swift:215-219) auto-creates a JournalEntry row (kind .attachment) alongside every attachment; delete(id:) removes only the Attachment row, so callers must not assume the journal entry is automatically cleaned.

TagStore.findOrCreate (TagStore+FindOrCreate.swift:34-41) uses case-insensitive match (==[c]) and never renames on collision; TagStore.create (TagStore.swift:37) calls uniqueNameUnder which appends a disambiguation suffix — these have different uniqueness semantics.
