# Diagnostic Logging & Package Export — Design

- **Date:** 2026-06-06
- **Status:** Approved (brainstorming complete); ready for implementation planning.
- **Platforms:** macOS + iOS (v1 covers both).
- **Motivation:** A self-serve, file-based diagnostic channel that records UI row
  manipulations and data-layer mutations to rolling on-device log files, plus a one-tap
  "diagnostic package" export, so issues like the reorder *"anchors out of order"* tie
  (`.rca/reorder-anchors-out-of-order/`) can be diagnosed from real captured data — including
  attribution of *which writer/process* produced a degenerate state.

## 1. Decisions (locked during brainstorming)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Log content | **Full content** (titles/notes included) | Pre-ship, single user, data disposable; logs stay on-device and only leave via explicit export. The toggle is the privacy control. |
| Platform scope | **macOS + iOS** | Dual-platform app; core capture is shared, both UIs built in v1. |
| Capture/persist architecture | **Per-process JSONL files in the App Group + export-time merge** (Approach ①) | Only option satisfying file-based + 30-day retention + cross-process capture + non-blocking; reuses existing App-Group patterns. |
| Toggle default | **On now; off at ship** via build-config (`Debug`/TestFlight on, `Release` off) | Automatic ship-flip, no reliance on memory. |
| Transmission | **Never auto-transmitted** | Logs leave only via user-initiated `.fileExporter` save. |

Rejected architectures: **OSLogStore harvesting** (the unified log can't guarantee 30-day
retention or reliable cross-process capture) and a **single shared file with
`NSFileCoordinator`** (per-event coordination latency can stall a drag; interleave/corruption
risk). See brainstorming transcript.

## 2. Architecture overview

```
                         ┌─────────────────────────────────────────────┐
   App process           │  LillistCore (shared, strict concurrency)    │
   Share Extension  ───▶ │                                              │
   App Intents ext.      │  ┌───────────────────┐   ┌────────────────┐  │
   (each its own         │  │ DiagnosticHistory │   │ explicit emits │  │
    process, shared      │  │ Observer (data    │   │ reorder/drag   │  │
    App-Group store)     │  │ events via NSPHT) │   │ (semantic/UI)  │  │
                         │  └─────────┬─────────┘   └───────┬────────┘  │
                         │            └────────┬────────────┘           │
                         │                  ┌──▼───────────┐            │
                         │   toggle ───────▶ │ DiagnosticLog │ (actor)   │
                         │ (DevicePrefs,     │  fire&forget  │           │
                         │  App-Group UD)    └──────┬────────┘           │
                         └──────────────────────────┼────────────────────┘
                                                    ▼
        App-Group/Lillist/Diagnostics/diag-<yyyy-MM-dd>-<process>.jsonl   (one per process/day)
                                                    │
                         ┌──────────────────────────▼─────────────────────┐
                         │ DiagnosticPackageBuilder (off main thread)       │
                         │  merge JSONL → events.jsonl + manifest.json      │
                         │  + optional consistent SQLite snapshot           │
                         │  → zip via NSFileCoordinator(.forUploading)      │
                         └──────────────────────────┬─────────────────────┘
                                                    ▼
                  Settings → "Prepare diagnostic package…" → include toggles
                            → .fileExporter (Files browser / save panel) → .zip
```

## 3. Type system (LillistCore)

```swift
public enum DiagProcess: String, Codable, Sendable { case app, shareExtension, appIntents, macApp, cli }
public enum DiagCategory: String, Codable, Sendable { case data, ui, lifecycle }

/// A typed leaf value so payloads stay structured but flexible.
public enum DiagValue: Codable, Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), null
}

/// One line in a JSONL diagnostic file.
public struct DiagnosticEvent: Codable, Sendable, Equatable {
    public let at: Date            // UTC, ISO-8601 on the wire
    public let seq: UInt64         // per-process monotonic; orders within the same ms
    public let process: DiagProcess
    public let category: DiagCategory
    public let name: String        // e.g. "task.reorder", "task.create", "drag.drop"
    public let payload: [String: DiagValue]
    public init(...)               // explicit public init (DTO rule)
}

/// Append-only writer. Never throws into callers.
public actor DiagnosticLog {
    public static func shared(process: DiagProcess, appGroupID: String) -> DiagnosticLog
    public func log(_ event: DiagnosticEvent)          // fire-and-forget at call sites
    public func droppedCount() -> Int                  // self-counted I/O failures
    // internals: resolve dir (App-Group → App-Support → no-op), open FileHandle,
    // day-rollover, 30-day prune on first write, JSONL encode (newline-safe).
}

/// Derives data events from persistent-history transactions (all writers, attributed).
public struct DiagnosticHistoryObserver { /* consumes NSPersistentHistoryTransaction */ }

/// Assembles the export .zip.
public struct DiagnosticPackageBuilder {
    public struct Options: Sendable { public var includeLogs: Bool; public var includeStore: Bool }
    public func build(options: Options) async throws -> URL   // temp .zip URL
}
```

Toggle lives in `DevicePreferencesStore` (App-Group `UserDefaults`, default from
`DiagnosticDefaults.enabledByDefault`, read by every process):
```swift
extension DevicePreferencesStore {
    func diagnosticLoggingEnabled() -> Bool          // default: DiagnosticDefaults.enabledByDefault
    func setDiagnosticLoggingEnabled(_ value: Bool)
}
public enum DiagnosticDefaults { public static let enabledByDefault: Bool = /* #if DEBUG true #else false #endif */ }
```

## 4. Event catalogue (key events)

| name | category | payload highlights |
|------|----------|--------------------|
| `task.create` | data/ui | `taskID, parentID, assignedPosition, observedMaxPosition, title, notes` |
| `task.reorder` | ui | `taskID, afterID, afterPosition, beforeID, beforePosition, computedPosition, didRecompact, threwError` |
| `task.reparent` | ui | `taskID, oldParentID, newParentID, assignedPosition` |
| `task.delete/move/change` | data | from history: `entity, objectUUID, op, changedProps[, position]`, `author` |
| `filter.reorder` | ui | SmartFilter analogue of `task.reorder` |
| `drag.start` | ui | `draggedID, sourceIndex` |
| `drag.over` | ui | `highlightTargetID, dropIndex` — **coalesced** (only on target change) |
| `drag.drop` | ui | `draggedID, resolution(reorder/reparent/noop), afterID, beforeID` |
| `cloudkit.import` | data | from history (author = mirroring delegate): position updates from other devices |

> The tie we root-caused would appear as two `task.create` (or a `cloudkit.import` position
> update) with the **same `assignedPosition`** but **different `author`/`process`**, then the
> `task.reorder` that threw — the full causal chain, on disk.

## 5. Capture strategy (emit points)

- **Data events → persistent history.** A `DiagnosticHistoryObserver` consumes the same
  `NSPersistentHistoryTransaction` stream already tracked by `RemoteChangeReconciler` /
  `PersistentHistoryTokenStore`. Logs entity, object UUID, op, changed property names (and the
  new `position`), and the transaction **author**. Because the app processes history authored
  by the extensions and by CloudKit imports, this captures *every* writer with attribution and
  **no per-extension instrumentation**. Requires each writer to stamp a distinct
  `transactionAuthor` (`app` / `shareExtension` / `appIntents`) — standardize (the reconciler
  already keys on authors).
- **Semantic + UI events → a few explicit calls:** `TaskStore.reorder` /
  `SmartFilterStore.reorder` (the anchor pair, even on the throwing path) and the shared drag
  layer (`DragController` + `DragDropResolver`, used by iOS `TasksView` and macOS
  `TaskListView`). Net new instrumentation ≈ 2 reorder callsites + 3 drag callsites + 1 observer.

## 6. Storage & rotation

- Path: App-Group `…/Lillist/Diagnostics/diag-<yyyy-MM-dd>-<process>.jsonl`. One file per
  process per day → no cross-process write contention.
- Writer: actor-held `FileHandle`, append `JSON + "\n"`, reopened on day-rollover/failure.
- Rotation: on first write of a session, prune `diag-*.jsonl` older than **30 days** (single scan).
- Fallback: App-Group unreachable → App-Support; else no-op.

## 7. Export flow

1. **Settings → `DiagnosticsSection`** (mirrors `CrashReportingSection`): toggle (bound to
   `DevicePreferencesStore.diagnosticLoggingEnabled`) + footnote + **"Prepare diagnostic
   package…"** button.
2. **Include step** (sheet): toggles **Diagnostic logs** (default on) and **Copy of data store**
   (default on; labeled as containing all task content) + size summary; Create / Cancel.
3. **`DiagnosticPackageBuilder.build`** (off main, with spinner):
   - merge JSONL → `events.jsonl` (sorted by `at`+`seq`), copy raw daily files, write `manifest.json`
     (build/OS/device, export time, toggle states, file inventory);
   - if `includeStore`: **consistent** SQLite snapshot — checkpoint WAL + copy `.sqlite`/`-wal`/`-shm`
     (or `VACUUM INTO`), not a torn live copy;
   - stage in temp dir, zip via `NSFileCoordinator(.forUploading)` → `Lillist-Diagnostics-<ts>.zip`.
4. **`.fileExporter`** presents the `.zip` (Files browser on iOS / save panel on macOS); temp cleaned up.

## 8. Error handling, performance, privacy

- **Resilience:** logging swallows all I/O errors (counts drops), never throws into callers — can't
  affect a drag or save. Package-assembly failures → dismissible Settings alert; store-copy failure
  → offer logs-only zip with a note.
- **Performance:** emission is fire-and-forget to the actor; toggle checked before encoding;
  history observer on the background path; `drag.over` coalesced to highlight-target changes; prune
  is one scan/session.
- **Privacy:** logs are as sensitive as the store → App-Group-local, never CloudKit-synced, never
  auto-transmitted. Default ships **off** via `DiagnosticDefaults.enabledByDefault` (Debug on /
  Release off). The crash-reporter/breadcrumb path is untouched.

## 9. Testing (TDD; warnings-as-errors; strict concurrency on source)

- `LillistCore` unit tests: `DiagnosticEvent` Codable/JSONL round-trip (newline-safe);
  `DiagnosticLog` append, per-process/day naming, **day rollover**, **30-day prune** (seed old files),
  toggle no-op, App-Group fallback, **concurrency stress** (mirror `BreadcrumbBuffer` tests).
- `DiagnosticHistoryObserver`: drive real store mutations → assert insert/update/delete + changed
  `position` + author; **regression test reproducing the create-tie** (two contexts, equal
  `assignedPosition`, distinct authors) asserting the log captures it.
- `DiagnosticPackageBuilder`: zip contains selected parts; merged events sorted; manifest present;
  store snapshot opens as valid SQLite with expected row counts; logs-only/store-only variants;
  temp cleanup.
- UI: container/presenter split → `DiagnosticsSection` + include sheet get LillistUI snapshot/tour
  coverage with mock state + closure-injected actions.
- Cross-process attribution can't run in CI; verified on a signed device (consistent with the repo's
  CI scope for app-hosted/iCloud tests).

## 10. Implementation surface (anticipated)

- **New (LillistCore):** `Diagnostics/DiagnosticEvent.swift`, `DiagnosticLog.swift`,
  `DiagnosticHistoryObserver.swift`, `DiagnosticPackageBuilder.swift`, `DiagnosticDefaults.swift`;
  `DevicePreferencesStore` toggle accessors; standardize `transactionAuthor` per writer.
- **Touch (LillistCore):** `TaskStore.reorder`/`create`/`reparent`, `SmartFilterStore.reorder`
  (explicit emits); persistence wiring for the history observer.
- **UI:** `LillistUI` presenter for the diagnostics section + include sheet; iOS
  `Settings/DiagnosticsSection.swift` + macOS Preferences pane; both wire `.fileExporter`.
- **Extensions:** honor the toggle + stamp `transactionAuthor` (no per-method logging).
- **Localization:** new user-visible strings synced across iOS app, macOS app, and LillistUI
  `Localizable.xcstrings` (cross-platform parity rule).
- **pbxproj:** regenerate via xcodegen after adding files.

## 11. Out of scope (YAGNI)

- Redaction tooling / anonymized log mode (the ship-off toggle is the privacy control for now).
- In-app log viewer, log search, or remote upload/telemetry.
- Configurable retention window (fixed 30 days).
- CLI export surface (the `lillist` CLI logs as a process but export is app-only in v1).

## 12. Relationship to the reorder bug

This feature is the instrumentation the RCA (`.rca/reorder-anchors-out-of-order/VERIFICATION.md`)
said was missing — per-create/per-reorder events with process/author attribution that would let us
confirm *which* writer minted a degenerate `position` tie. It is complementary to, not a substitute
for, the ordering-invariant fix (atomic/coordinated allocation + self-healing reorder + load-time
normalization) tracked separately.
```
