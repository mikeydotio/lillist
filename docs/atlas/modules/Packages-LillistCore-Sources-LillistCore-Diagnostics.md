---
module: Packages/LillistCore/Sources/LillistCore/Diagnostics
summary: "Opt-in JSONL event logger, Core Data history bridge, and zip-package exporter for in-app diagnostics"
read_when: "Touching diagnostics or history observation"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticDefaults.swift
    blob: e3f22151361ded3a01d1bcc2601f0a62ed095d8f
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift
    blob: 4b41a93037c2cd610c2b5be293eaaab663cdef1e
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift
    blob: b9e07971ffd2c766b0df00813d441ad9e83e56d8
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift
    blob: 0ac37c8392163db4b229f840218f263f1f5585bf
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift
    blob: 772bff36cf58e6287890ac6c06167120e774264f
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift
    blob: e2584a0372a51010539bd69615fad14ed4e1d39a
references_modules: [Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Recurrence, Packages-LillistUI-Sources-LillistUI-Accessibility, Packages-LillistUI-Sources-LillistUI-Editor, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Packages/LillistCore/Sources/LillistCore/Diagnostics

## Purpose

Provides the complete opt-in, append-only diagnostic logging pipeline: a structured event model (DiagnosticEvent + DiagValue), a per-process JSONL actor writer (DiagnosticLog), a Core Data persistent-history bridge that turns store mutations into structured events (DiagnosticHistoryObserver), and a zip-package assembler that merges logs and snapshots the SQLite store for export (DiagnosticPackageBuilder). The module's unifying idea is fire-and-forget observability — I/O failures are counted, never propagated, so logging can never affect any user-facing operation. Without it there is no persistent structured trace of what the app did to its data, leaving crash reports and sync anomalies diagnosable only by heuristics.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `BuildError` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:41` | Sealed error cases for build failures; snapshotFailed carries the SQLite error message; zipProducedNothing signals coordinator produced nothing. |
| `DiagCategory` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:10` | Three-case coarse triage tag (data/ui/lifecycle); raw String values are stable across JSONL files. |
| `DiagProcess` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:5` | Identifies the writing process and names the per-day JSONL file; raw String values must remain stable. |
| `DiagValue` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:20` | Typed payload leaf; callers rely on the intentional int/double normalization: integral doubles encode as JSON integers and decode as .int. |
| `DiagnosticDefaults` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticDefaults.swift:10` | Compile-time constant: true in DEBUG builds, false in Release; the user-facing preference always overrides this default. |
| `DiagnosticEvent` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:50` | Immutable JSONL record; Codable + Equatable; encodeJSONLine/decodeJSONLine round-trips as exactly one physical line. |
| `DiagnosticHistoryObserver` | class | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:20` | Observes NSPersistentStoreRemoteChange and emits structured events to a DiagnosticSink; start/stop lifecycle; processPendingHistory is reentrancy-safe. |
| `DiagnosticLog` | actor | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:12` | Append-only actor; log() is fire-and-forget and never throws into callers; I/O failures increment dropped only. |
| `DiagnosticLog` | extension | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift:11` | Conformance declaration only; the async log(_ event:) implementation is on the DiagnosticLog actor. |
| `DiagnosticPackageBuilder` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:10` | Value-typed, Sendable export builder; each stage/build call is stateless — construct a new instance per export request. |
| `DiagnosticSink` | protocol | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift:7` | Single async requirement log(_ event:); Sendable; production conformer is DiagnosticLog; tests inject an in-memory spy. |
| `HistoryChange` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:23` | Sendable value snapshot of one persistent-history change; fully resolved against the live context inside ctx.perform before crossing async boundaries. |
| `Metadata` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:21` | Codable manifest header; files and notes are mutable and filled during staging; callers may read them after stage() returns. |
| `Options` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:11` | Two Boolean flags controlling what stage() includes; callers set includeLogs/includeStore independently. |
| `build` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:168` | Async; stages, zips, and cleans up the staging dir; returns a temp URL the caller must move before it expires. |
| `decodeJSONLine` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:87` | Throws on malformed input; a torn write corrupts at most one line; succeeds only for a complete, valid JSON object. |
| `decodeJSONLines` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:91` | Splits blob by newline and decodes each line; corrupt lines propagate as throws (caller gets an array or an error, never a partial result). |
| `diagnosticsDirectory` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:66` | Returns the URL the log writes to; nil means logging is a no-op; DiagnosticPackageBuilder uses this to locate JSONL files. |
| `droppedCount` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:62` | Returns the count of events silently discarded due to I/O failure since construction; useful for diagnosing whether logging is functional. |
| `encode` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:32` | Custom encode for DiagValue; integral doubles encode as JSON integers — this normalization is by design and must not be changed. |
| `encodeJSONLine` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:82` | Returns compact JSON + a literal newline; the trailing newline is the JSONL contract — callers may append the string directly to a file. |
| `finishOrRerun` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:75` | Actor method on DrainGate; returns true if the owning drainer should sweep again (a request arrived mid-drain), false to stop. |
| `log` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:70` | Fire-and-forget append; overwrites the emitter's process and seq placeholders with the authoritative values from the log actor. |
| `log` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:143` | Get-or-create from the per-process SharedRegistry; synchronous; the same DiagProcess always returns the same actor instance. |
| `log` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift:8` | Async protocol requirement; callers must await; the DiagnosticLog implementation is synchronous (actor isolation, no real suspension). |
| `manifestEncoder` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:212` | Returns a pretty-printed, sorted-keys, ISO-8601 JSONEncoder for human-readable manifests; stable output format. |
| `mergeEvents` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:199` | Line-by-line decode; a corrupt or torn line is silently skipped (raw files are preserved); returns at/seq-sorted merged timeline. |
| `processPendingHistory` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:131` | Reentrancy-safe drain: only one pass runs at a time; concurrent calls coalesce into a single follow-up pass, so no change is double-emitted or missed. |
| `pruneOldFiles` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:121` | Deletes diag-*.jsonl files whose UTC day stamp is older than days before now; safe to call multiple times; also run automatically on first log call. |
| `resolveDirectory` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:50` | Returns the App-Group Lillist/Diagnostics URL, falling back to Application Support, then nil; used at construction to seed the directory. |
| `setEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:61` | Mutates the enabled flag on the actor; subsequent log() calls reflect the new value; call after reading DevicePreferencesStore. |
| `shared` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:44` | Per-process singleton; synchronous; idempotent — the same DiagProcess key always returns the same actor; first caller's enabled seeds it. |
| `snapshotStore` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:150` | Opens the live store read-only and runs VACUUM INTO; dest must not already exist; SQLite errors throw BuildError.snapshotFailed. |
| `stage` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:73` | Builds the unzipped staging folder and returns its URL; store-snapshot failure degrades to a manifest note rather than throwing; caller owns cleanup of the returned URL's parent. |
| `start` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:102` | Idempotent (guards on observer == nil); registers the NSPersistentStoreRemoteChange observer; call once at bootstrap. |
| `stop` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:114` | Removes the NSPersistentStoreRemoteChange observer; safe to call multiple times; also called by deinit. |
| `tryAcquire` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:69` | Actor method on DrainGate; returns true if this caller becomes the single owning drainer, false if a drain is already in flight. |
| `utcDayStamp` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:152` | Returns UTC yyyy-MM-dd string; must remain UTC for cross-device log merges; lexical order equals chronological order. |
| `zip` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:222` | Uses NSFileCoordinator(.forUploading) to produce a zip; copies it to a stable temp URL before the accessor block returns; caller owns the returned URL. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `flatten` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:184` | Guards against Obj-C KVC exceptions by checking attributesByName before calling value(forKey:); handles delete-tombstone nil-UUID gap; captures create-time position for LillistTask inserts even when updatedProperties is nil — all three invariants must hold for the diagnostic history to be correct and crash-free. |
| `makeDecoder` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:74` | Guards ISO-8601 date decoding strategy for all DiagnosticEvent round-trips; silently changing it would corrupt dates in every decoded log file while encode continued producing ISO-8601 strings. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Diagnostics.BuildError -> Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagValue -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.decodeJSONLines -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.encode -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.encode -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.encodeJSONLine -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.flatten -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.makeDecoder -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.mergeEvents -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.opName -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.processPendingHistory -> Packages-LillistCore-Sources-LillistCore-Recurrence.advance (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.reserveSeqs -> Packages-LillistUI-Sources-LillistUI-Accessibility.value (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.snapshotStore -> Packages-LillistCore-Sources-LillistCore-LinkPreview.String (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.stage -> Packages-LillistUI-Sources-LillistUI-Editor.note (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.utcDayStamp -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`

## Type notes

DiagnosticLog is a public actor (DiagnosticLog.swift:12); its shared factory is synchronous via a lock-protected SharedRegistry class (DiagnosticLog.swift:139–150) because callers cannot await at call sites. The enabled flag is a cached Bool mutated by setEnabled (DiagnosticLog.swift:61) so log() never suspends on DevicePreferencesStore. DiagnosticHistoryObserver is @unchecked Sendable (DiagnosticHistoryObserver.swift:20): the NSObjectProtocol observer token is main-actor-touched only in start/stop, DrainGate (a nested private actor) guards the drain-coalesce state, and seqLock (NSLock) guards the UInt64 sequence counter (DiagnosticHistoryObserver.swift:49–60). DiagnosticSink is the injectable protocol (DiagnosticSink.swift:7); DiagnosticLog conforms in production (DiagnosticSink.swift:11); tests inject an in-memory spy, keeping observers and stores off disk. DiagnosticPackageBuilder is a Sendable struct (DiagnosticPackageBuilder.swift:10), deliberately value-typed so each export request gets a fresh instance with no lifecycle coupling.

## External deps

- CoreData — imported
- Foundation — imported
- SQLite3 — imported

## Gotchas

DrainGate is a private actor nested inside DiagnosticHistoryObserver (DiagnosticHistoryObserver.swift:64) specifically because NSLock.lock() is unavailable across async suspension points — the coalesce pattern needs an actor to be safe under Swift 6 strict concurrency (DiagnosticHistoryObserver.swift:52–59). DiagnosticLog.shared is synchronous (can't await), so its per-process registry cannot be an actor; instead a lock-protected SharedRegistry class guards it under @unchecked Sendable (DiagnosticLog.swift:139–150). DiagValue intentionally normalizes integral doubles to .int on decode: a JSON number like 2.0 encodes as 2 and decodes as .int(2) — by design, not a bug (DiagnosticEvent.swift:15–19). Delete tombstones in persistent history do not carry the id attribute unless preserveValueInHistoryOnDeletion is set; delete events currently resolve nil objectUUID and are attributed by entity+author only — deferred model change, noted in code (DiagnosticHistoryObserver.swift:196–202). NSFileCoordinator(.forUploading) hands zip to a transient URL that is reclaimed after the accessor block; the builder copies it to a stable temp URL before the block returns (DiagnosticPackageBuilder.swift:194–200).
