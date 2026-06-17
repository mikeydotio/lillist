---
module: Packages/LillistCore/Sources/LillistCore/Diagnostics
summary: "On-disk JSONL diagnostic event log, history-derived attribution, and export-package builder"
read_when: "Diagnostic logging & export"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticDefaults.swift
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift
  - path: Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2, Packages-LillistUI-Sources-LillistUI-DragReorder, Apps-Lillist-iOS-Sources-App, Apps-Lillist-macOS-Sources-Preferences, Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore/Diagnostics

## Purpose

A fire-and-forget diagnostics subsystem: emitters (stores, drag gestures, a
history observer) hand `DiagnosticEvent`s to a `DiagnosticSink`, the production
sink (`DiagnosticLog`) appends them as one-line JSON to per-process-per-day
JSONL files, and `DiagnosticPackageBuilder` later zips those logs plus a SQLite
store snapshot into a shareable RCA package. The design idea is *non-intrusive
attribution*: logging never throws, blocks, or affects a caller, yet the
history observer can reconstruct who wrote what (e.g. a reorder tie) after the
fact. If it vanished, the app loses its only persistent field-debugging trail.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `DiagCategory` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:10` | Coarse triage class: `data`/`ui`/`lifecycle` |
| `DiagnosticDefaults` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticDefaults.swift:10` | `enabledByDefault` — on in Debug, off in Release |
| `DiagnosticEvent` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:50` | Codable value DTO; `encodeJSONLine`/`decodeJSONLine(s)` are the wire format |
| `DiagnosticHistoryObserver` | class | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:20` | Observes persistent-history, emits `<entity>.<op>` events to a sink |
| `DiagnosticLog` | actor | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:12` | Per-process singleton JSONL writer; `log` never throws |
| `DiagnosticPackageBuilder` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:10` | Stages + zips logs and a store snapshot into an export `.zip` |
| `DiagnosticSink` | protocol | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticSink.swift:7` | `func log(_:) async` — the seam emitters depend on, not the actor |
| `DiagProcess` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:5` | Authoring process; also names the JSONL file |
| `DiagValue` | enum | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:20` | Typed payload leaf; integral doubles normalize to `.int` |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `shared` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:44` | Synchronous per-process factory; entry point every host calls |
| `setEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:61` | Mutates the cached `enabled` Bool so `log` skips an `await` on the hot path |
| `diagnosticsDirectory` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:66` | Single source of the on-disk path shared by writer and exporter |
| `processPendingHistory` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:131` | Reentrancy-safe drain; coalesces overlapping notifications, no double-emit |
| `makeEvents` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:239` | Pure `nonisolated static` event builder; testable without a context |
| `Metadata` | struct | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:21` | `manifest.json` shape: build/OS/device + file inventory + notes |
| `mergeEvents` | func | `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:163` | Per-line-resilient merge of all files into one `at`/`seq` timeline |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (calls)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController (reads)`
- `Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver -> Packages-LillistCore-Sources-LillistCore-Persistence.PersistentHistoryTokenStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (calls)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragController -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticLog (calls)`
- `Apps-Lillist-iOS-Sources-App.AppEnvironment -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticHistoryObserver (owns)`
- `Apps-Lillist-macOS-Sources-Preferences.DiagnosticsPane -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticPackageBuilder (calls)`
- `Packages-LillistCore-Sources-LillistCore-CLIBridge-Handlers-chunk-1.AddHandler -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticSink (calls)`

## Type notes

`DiagnosticLog` is an actor; its `enabled` flag is a cached `Bool` set at
construction and mutated only via `setEnabled`, so `log` never awaits
`DevicePreferencesStore` (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:12`). The actor owns the
authoritative `process` and the per-file monotonic `seq`; emitters pass
placeholder values that `log` overwrites (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:70`). `shared`
is backed by a lock-guarded `SharedRegistry` (not an actor) precisely because
the factory is synchronous (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:139`).

`DiagnosticHistoryObserver` is `@unchecked Sendable`: the observer token is
touched on the main actor, the token store is thread-safe, and `seq` is
lock-guarded (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:20`). Its `DrainGate` actor
enforces a single in-flight drain so the split watermark read-modify-write
(read inside `perform`, advance after the emit loop) never double-emits
(`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:64`). It uses its own watermark key,
`PersistentHistoryTokenStore.diagnosticsKey`, to avoid clobbering the
reconciler (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:84`).

`DiagnosticEvent` guarantees exactly one physical line per event because
`JSONEncoder` escapes embedded newlines (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift:80`). A store
snapshot failure degrades the package to logs-only with a manifest note rather
than aborting (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift:99`).

## External deps

- Foundation — `FileManager`, `FileHandle`, `JSONEncoder/Decoder`, `NSFileCoordinator`
- CoreData — `NSPersistentHistoryChangeRequest`, remote-change notification, history transactions
- SQLite3 — `VACUUM INTO` produces a consistent read-only store snapshot

## Gotchas

- Delete events resolve a nil `objectUUID`: `id` is not flagged `preserveValueInHistoryOnDeletion`, so tombstones lack it (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:194`).
- `flatten` reads `id`/`position` via `attributesByName` guards because `value(forKey:)` on an undeclared key raises an uncatchable Obj-C exception (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift:180`).
- Retention prune relies on lexical comparison of zero-padded `yyyy-MM-dd` stamps and assumes process names contain no `-` (`Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift:127`).
