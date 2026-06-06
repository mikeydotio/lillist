# Diagnostic Logging & Package Export — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Use the **ios-tdd** skill for every Swift Red→Green→Refactor cycle.

**Goal:** Add an on-by-default (off-at-ship) file-based diagnostic logging channel for macOS + iOS that records UI row-manipulations and data-layer mutations to rolling 30-day per-process JSONL files in the App Group, plus a "Prepare diagnostic package" Settings flow that zips logs + an optional consistent data-store snapshot and saves via the Files browser.

**Architecture:** A `DiagnosticLog` actor (mirrors `BreadcrumbBuffer`) appends JSONL to `App-Group/Lillist/Diagnostics/diag-<yyyy-MM-dd>-<process>.jsonl`. Data events come from a `DiagnosticHistoryObserver` (clone of `RemoteChangeReconciler`, own token watermark) that attributes each mutation to its writing process via `transactionAuthor`; semantic reorder/create/reparent + drag events are emitted explicitly. `DiagnosticPackageBuilder` merges logs + a `VACUUM INTO` SQLite snapshot and zips via `NSFileCoordinator(.forUploading)`; SwiftUI `.fileExporter` saves it.

**Tech Stack:** Swift 6 (strict concurrency on LillistCore source, warnings-as-errors), Core Data / `NSPersistentCloudKitContainer` + persistent history, SwiftUI, `import SQLite3` (system), Foundation `NSFileCoordinator`. No new SPM dependencies.

---

## Pre-flight — read before Task 1

**Design:** `docs/plans/2026-06-06-diagnostic-logging-design.md` (sections referenced as §N below).

**Critical findings from recon that this plan acts on:**
1. **`transactionAuthor` is a single shared constant** `PersistenceController.localTransactionAuthor = "Lillist.app"` (`PersistenceController.swift:33`), stamped on `viewContext` (:67-68) and every `makeBackgroundContext()` (:121). The app, Share Extension, App Intents extension and CLI all stamp the *same* author. **Per-process attribution (the whole point) is net-new** — Phase 2 threads a per-process author through `PersistenceController.init`, keeping the app's author classified as "local" in `RemoteChangeReconciler.affectedTaskIDs` (:144-165).
2. **Only the iOS app wires a history consumer.** macOS has no `RemoteChangeReconciler`. The `DiagnosticHistoryObserver` is net-new wiring on **both** platforms and **must use its own** `PersistentHistoryTokenStore` key (NOT the reconciler's `com.mikeydotio.lillist.persistentHistoryToken`) or the two consumers clobber each other's watermark.
3. **`DevicePreferencesStore` is an `actor`** — a SwiftUI `Toggle` can't bind to it and `DiagnosticLog.log` can't `await` it per event. The log holds a **cached `Bool`** set at construction and updated on toggle change; Settings hydrates a local `@State` in `.task` and writes back in `.onChange`.
4. **The live store can't be closed** for the snapshot. `QuarantineManager.copyStore` (:89-118) copies `-wal`/`-shm` sidecars but does **not** checkpoint. Use **`VACUUM INTO`** (via `import SQLite3`, read-only open) to produce one consistent file. In-memory stores (tests) have no URL → the store-include branch no-ops.
5. **No zip/`.fileExporter` exists in the repo.** Use Foundation `NSFileCoordinator().coordinate(readingItemAt:options:.forUploading)` to zip a staging dir (copy the produced `.zip` out before the block returns). No ZIPFoundation/SPM dep (YAGNI).
6. **`nextPosition` (`TaskStore.swift:685`) discards the observed max** — surface it so `task.create` can log `observedMaxPosition`.
7. **`SmartFilterStore` has no `breadcrumbs`/`recordCrumb`/do-catch** — adding `filter.reorder` (esp. `threwError`) is net-new sink + do/catch there.
8. **House rules:** strict concurrency on LillistCore source (tests not strict); warnings-as-errors all targets; hand-written DTOs need explicit `public init`; never let `NSManagedObject`/`NSPersistentHistoryToken` escape a `perform` block; 3 `Localizable.xcstrings` stay verbatim-aligned + `Tools/CI/check-lillistui-localization.sh`; regenerate **both** pbxprojs after new **app-target** files (package files don't need it).

**Branch:** work continues on `feat/diagnostic-logging` (design doc already committed there).

**Test commands (per CLAUDE.md):**
- LillistCore: `swift test --package-path Packages/LillistCore --parallel --num-workers 2` (re-run once on a one-off SIGSEGV/timing flake).
- LillistUI compile + non-snapshot: `swift test --package-path Packages/LillistUI --skip Snapshot --skip Tour`.
- iOS bundle / snapshots / app-hosted: `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'` (signed Mac only for app-hosted + snapshot).
- Per CLAUDE.md, after adding **app-target** files: `(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)` then `(cd Apps && xcodegen generate --spec project.yml --project .)`.

**Test scoping (design §9):** unit tests (JSONL round-trip, naming, day rollover, 30-day prune, toggle no-op, App-Group fallback, concurrency stress, package builder, same-container two-context tie) run under `swift test`. Live cross-process/CloudKit attribution + UI snapshot/tour are signed-Mac only — mark them accordingly, don't expect them in CI.

---

## Phase 0 — Event model & preferences (LillistCore, no UI)

### Task 1: `DiagProcess` / `DiagCategory` / `DiagValue` / `DiagnosticEvent`

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticEventTests.swift`

**Step 1 — failing test** (`DiagnosticEventTests.swift`):
```swift
import XCTest
@testable import LillistCore

final class DiagnosticEventTests: XCTestCase {
    func test_jsonl_roundTrips_singleLine_noEmbeddedNewlines() throws {
        let event = DiagnosticEvent(
            at: Date(timeIntervalSince1970: 1_700_000_000),
            seq: 7,
            process: .app,
            category: .ui,
            name: "task.reorder",
            payload: ["afterPosition": .double(2.0), "title": .string("buy milk\nand eggs"), "threwError": .bool(true), "parentID": .null]
        )
        let line = try DiagnosticEvent.encodeJSONLine(event)
        XCTAssertFalse(line.dropLast().contains("\n"), "only the trailing terminator may be a newline")
        XCTAssertTrue(line.hasSuffix("\n"))
        let decoded = try DiagnosticEvent.decodeJSONLine(line)
        XCTAssertEqual(decoded, event)
    }

    func test_decodes_a_full_file_of_lines() throws {
        let a = DiagnosticEvent(at: Date(timeIntervalSince1970: 1), seq: 1, process: .shareExtension, category: .data, name: "task.create", payload: [:])
        let b = DiagnosticEvent(at: Date(timeIntervalSince1970: 2), seq: 2, process: .app, category: .data, name: "task.delete", payload: [:])
        let blob = try DiagnosticEvent.encodeJSONLine(a) + DiagnosticEvent.encodeJSONLine(b)
        XCTAssertEqual(try DiagnosticEvent.decodeJSONLines(blob), [a, b])
    }
}
```

**Step 2 — run, expect FAIL** (`DiagnosticEvent` undefined):
`swift test --package-path Packages/LillistCore --filter DiagnosticEventTests`

**Step 3 — implement** (`DiagnosticEvent.swift`) — mirror `Breadcrumb`/`CrashReport` DTO discipline (explicit public inits):
```swift
import Foundation

public enum DiagProcess: String, Codable, Sendable {
    case app, macApp, shareExtension, appIntents, cli
}

public enum DiagCategory: String, Codable, Sendable {
    case data, ui, lifecycle
}

/// A typed leaf so payloads stay structured but flexible.
public enum DiagValue: Codable, Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

/// One line in a per-process JSONL diagnostic file.
public struct DiagnosticEvent: Codable, Sendable, Equatable {
    public let at: Date
    public let seq: UInt64
    public let process: DiagProcess
    public let category: DiagCategory
    public let name: String
    public let payload: [String: DiagValue]

    public init(at: Date, seq: UInt64, process: DiagProcess, category: DiagCategory, name: String, payload: [String: DiagValue]) {
        self.at = at; self.seq = seq; self.process = process
        self.category = category; self.name = name; self.payload = payload
    }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return e
    }
    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    /// One compact JSON object + "\n". JSONEncoder never emits raw newlines
    /// inside a value (they're escaped as \n), so each event is exactly one line.
    public static func encodeJSONLine(_ event: DiagnosticEvent) throws -> String {
        let data = try makeEncoder().encode(event)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    public static func decodeJSONLine(_ line: String) throws -> DiagnosticEvent {
        try makeDecoder().decode(DiagnosticEvent.self, from: Data(line.utf8))
    }
    public static func decodeJSONLines(_ blob: String) throws -> [DiagnosticEvent] {
        try blob.split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decodeJSONLine(String($0)) }
    }
}
```

**Step 4 — run, expect PASS.**

**Step 5 — commit:**
```bash
git add Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticEvent.swift Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticEventTests.swift
git commit -m "feat(diagnostics): DiagnosticEvent JSONL value model"
```

### Task 2: `DiagnosticDefaults.enabledByDefault`

**Files:** Create `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticDefaults.swift`. (No dedicated test — it's a compile-time constant; exercised by Task 3.)

**Implementation** (mirrors the existing `#if DEBUG` at `CloudKitSchemaInitializer.swift:31`):
```swift
import Foundation

/// On-by-default during development; flips OFF in Release (App Store) builds.
/// deployit archives Debug, so TestFlight/dev builds log by default; only a
/// true Release config disables logging at ship (design §1, §8).
public enum DiagnosticDefaults {
    public static let enabledByDefault: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}
```
**Commit:** `feat(diagnostics): DiagnosticDefaults build-config default`

### Task 3: `DevicePreferencesStore` toggle accessors

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift` (after the crash-prompts block, ~:113)
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Preferences/DevicePreferencesDiagnosticToggleTests.swift`

**Step 1 — failing test:**
```swift
import XCTest
@testable import LillistCore

final class DevicePreferencesDiagnosticToggleTests: XCTestCase {
    func test_defaults_to_DiagnosticDefaults_when_unset() async {
        let suite = "test.diag.\(UUID().uuidString)"
        let store = DevicePreferencesStore(suiteName: suite)
        let value = await store.diagnosticLoggingEnabled()
        XCTAssertEqual(value, DiagnosticDefaults.enabledByDefault)
    }
    func test_persists_explicit_value() async {
        let suite = "test.diag.\(UUID().uuidString)"
        let store = DevicePreferencesStore(suiteName: suite)
        await store.setDiagnosticLoggingEnabled(false)
        let reread = DevicePreferencesStore(suiteName: suite)
        let value = await reread.diagnosticLoggingEnabled()
        XCTAssertFalse(value)
    }
}
```

**Step 2 — run, expect FAIL.**

**Step 3 — implement** (mirror `crashPromptsEnabled` at :102-113):
```swift
    // MARK: Diagnostic logging

    private static let diagnosticLoggingKey = "lillist.devicePrefs.diagnosticLoggingEnabled"
    /// Whether file-based diagnostic logging is active on this device.
    /// Default sourced from `DiagnosticDefaults` (on in Debug, off in Release).
    /// Device-local + App-Group-shared so every process reads the same value.
    public func diagnosticLoggingEnabled() -> Bool {
        if defaults.object(forKey: Self.diagnosticLoggingKey) == nil {
            return DiagnosticDefaults.enabledByDefault
        }
        return defaults.bool(forKey: Self.diagnosticLoggingKey)
    }
    public func setDiagnosticLoggingEnabled(_ value: Bool) {
        defaults.set(value, forKey: Self.diagnosticLoggingKey)
    }
```

**Step 4 — run, expect PASS.** **Step 5 — commit:** `feat(diagnostics): device-local diagnostic-logging toggle`

---

## Phase 1 — The writer (`DiagnosticLog` actor)

### Task 4: `DiagnosticLog` — resolution, append, cached-enabled no-op, drop count

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticLog.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticLogTests.swift`

Design notes: mirror `BreadcrumbBuffer` (actor, `public init`, fire-and-forget, never throws). Dir resolution mirrors `CanaryFile`/`StoreConfiguration.appGroupOnDisk` (App-Group → temp/App-Support → no-op). The enabled flag is a **cached Bool** (set at construction, mutable via `setEnabled`) so `log` never awaits `DevicePreferencesStore`. For tests, add an init that takes an explicit directory URL + enabled flag.

**Step 1 — failing tests** (representative; add the full set):
```swift
import XCTest
@testable import LillistCore

final class DiagnosticLogTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("diaglog-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func event(_ name: String, _ seq: UInt64) -> DiagnosticEvent {
        DiagnosticEvent(at: Date(timeIntervalSince1970: 1_700_000_000), seq: seq, process: .app, category: .data, name: name, payload: [:])
    }

    func test_append_writes_one_jsonl_line_per_event_to_process_day_file() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: true, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        await log.log(event("task.delete", 2))
        let file = dir.appendingPathComponent("diag-2026-06-06-app.jsonl")
        let lines = try DiagnosticEvent.decodeJSONLines(String(contentsOf: file, encoding: .utf8))
        XCTAssertEqual(lines.map(\.name), ["task.create", "task.delete"])
    }

    func test_disabled_log_is_a_noop() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: false, dayStamp: "2026-06-06")
        await log.log(event("task.create", 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("diag-2026-06-06-app.jsonl").path))
    }

    func test_setEnabled_toggles_writing() async throws {
        let dir = tempDir()
        let log = DiagnosticLog(directory: dir, process: .app, enabled: false, dayStamp: "2026-06-06")
        await log.setEnabled(true)
        await log.log(event("task.create", 1))
        let file = dir.appendingPathComponent("diag-2026-06-06-app.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
```

**Step 2 — run, expect FAIL.**

**Step 3 — implement** (`DiagnosticLog.swift`). Key points: actor; opens/creates the day file lazily via `FileHandle`; `dayStamp` injectable for tests, otherwise derived from a UTC `DateFormatter`; never throws (increments `dropped`). Sketch:
```swift
import Foundation

public actor DiagnosticLog {
    private let directory: URL?
    private let process: DiagProcess
    private var enabled: Bool
    private let fixedDayStamp: String?
    private var dropped: Int = 0
    private var handle: FileHandle?
    private var openDayStamp: String?

    /// Test/explicit init.
    public init(directory: URL?, process: DiagProcess, enabled: Bool, dayStamp: String? = nil) {
        self.directory = directory; self.process = process
        self.enabled = enabled; self.fixedDayStamp = dayStamp
    }

    public func setEnabled(_ value: Bool) { enabled = value }
    public func droppedCount() -> Int { dropped }

    public func log(_ event: DiagnosticEvent) {
        guard enabled, let directory else { return }
        do {
            let stamp = fixedDayStamp ?? Self.utcDayStamp(event.at)
            let handle = try fileHandle(for: stamp, in: directory)
            let line = try DiagnosticEvent.encodeJSONLine(event)
            try handle.write(contentsOf: Data(line.utf8))
        } catch { dropped += 1 }
    }

    private func fileHandle(for stamp: String, in dir: URL) throws -> FileHandle {
        if let handle, openDayStamp == stamp { return handle }   // day rollover (Task 5) closes/reopens
        try? handle?.close()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("diag-\(stamp)-\(process.rawValue).jsonl")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        handle = h; openDayStamp = stamp
        return h
    }

    static func utcDayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
```

**Step 4 — run, expect PASS.** **Step 5 — commit:** `feat(diagnostics): DiagnosticLog actor (append + cached-enabled no-op)`

### Task 5: Day rollover + 30-day prune

**Files:** Modify `DiagnosticLog.swift`; add tests to `DiagnosticLogTests.swift`.

**Step 1 — failing tests:** (a) events on different `dayStamp`s write to different files and the handle reopens; (b) `pruneOldFiles(olderThanDays: 30, now:)` deletes `diag-*.jsonl` whose date is >30 days before `now` and keeps newer ones (seed files with `FileManager` + back-dated names, assert which survive).

**Step 3 — implement:** rollover already handled by `openDayStamp != stamp` in `fileHandle`. Add:
```swift
    public func pruneOldFiles(olderThanDays days: Int, now: Date) {
        guard let directory else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now) ?? now
        let cutoffStamp = Self.utcDayStamp(cutoff)
        for f in files where f.lastPathComponent.hasPrefix("diag-") && f.pathExtension == "jsonl" {
            // diag-<yyyy-MM-dd>-<process>.jsonl
            let parts = f.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard parts.count >= 4 else { continue }
            let stamp = "\(parts[1])-\(parts[2])-\(parts[3])"
            if stamp < cutoffStamp { try? FileManager.default.removeItem(at: f) }   // lexical compare valid for yyyy-MM-dd
        }
    }
```
Call `pruneOldFiles` once per process at first `log` (guard with a `didPrune` flag) — add that guard in `log`.

**Step 4 — PASS. Step 5 — commit:** `feat(diagnostics): day rollover + 30-day prune`

### Task 6: Concurrency stress test + `shared(process:appGroupID:)` factory

**Files:** Modify `DiagnosticLog.swift` (add the App-Group factory); add stress test (mirror `BreadcrumbBuffer` concurrency tests).

- Factory: `public static func shared(process: DiagProcess, appGroupID: String, enabled: Bool) -> DiagnosticLog` — resolves `containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?.appendingPathComponent("Lillist/Diagnostics", isDirectory: true)`; if nil, fall back to App-Support `Lillist/Diagnostics`; pass that URL to `init`. (Per-process singleton: hold a `static` cache keyed by process if a process could request twice — App Intents caches its controller per-process, IntentSupport.swift:19-59.)
- Stress test: spawn N concurrent `Task`s each calling `log` 25× with distinct `seq`; await all; assert the file has exactly N×25 well-formed lines (decode the file). Run under `--num-workers 2` tolerance.

**Commit:** `test(diagnostics): DiagnosticLog concurrency stress + App-Group factory`

---

## Phase 2 — Per-process `transactionAuthor` (attribution prerequisite)

### Task 7: Thread a per-process author through `PersistenceController`

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Persistence/PersistenceController.swift` (:33, :35 init, :67-68, :121)
- Modify callers that must stamp distinct authors: `Extensions/ShareExtension-iOS/ShareRootView.swift` (:77-83), `Extensions/ShortcutsActions/IntentSupport.swift` (:73-82), via `GatedPersistenceResolver` (`makePersistence`).
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Persistence/TransactionAuthorTests.swift`

**Design:** add `public init(configuration: StoreConfiguration, transactionAuthor: String = PersistenceController.localTransactionAuthor) async throws`; stamp `transactionAuthor` on viewContext + background contexts. Keep `localTransactionAuthor = "Lillist.app"` as the default so existing app behavior + `RemoteChangeReconciler.affectedTaskIDs(localAuthor:)` classification is unchanged. Introduce author constants: `"Lillist.app"`, `"Lillist.shareExtension"`, `"Lillist.appIntents"`, `"Lillist.macApp"`, `"Lillist.cli"`. Thread the author through `GatedPersistenceResolver.makePersistence` (add an optional author param, default app).

**Step 1 — failing test:** build a `PersistenceController(configuration: .inMemory, transactionAuthor: "Lillist.shareExtension")`, perform a create on a background context, fetch persistent history via `NSPersistentHistoryChangeRequest.fetchHistory(after: nil)`, assert the last transaction's `author == "Lillist.shareExtension"`. Also assert default init still yields `"Lillist.app"`.

**Step 2 — run FAIL** (init has no author param).

**Step 3 — implement** the param + stamping. (Keep the `localTransactionAuthor` constant for the default and for the reconciler's local classification.)

**Step 4 — PASS.**

**Step 5 — verify the reconciler unaffected:** run `swift test --package-path Packages/LillistCore --filter RemoteChange` — expect PASS. **Commit:** `feat(diagnostics): per-process Core Data transactionAuthor` (extension wiring lands in Task 17).

---

## Phase 3 — Data-event capture (`DiagnosticHistoryObserver`)

### Task 8: `DiagnosticHistoryObserver` (own watermark, attribute + emit)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticHistoryObserver.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticHistoryObserverTests.swift`

**Design:** clone `RemoteChangeReconciler` (`@unchecked Sendable` final class; `start()`/`processPendingHistory()`; read token inside `ctx.perform`; never let the token/NSManagedObject escape). Use a **distinct** UserDefaults watermark key `io.mikeydotio.lillist.diagnostics.historyToken` (own `PersistentHistoryTokenStore`-style store, or parameterize the key). For each `txn`/`change`: capture `entityName`, `txn.author`, `change.updatedProperties` names; resolve the object UUID + (for `position` changes) the new `position` via `ctx.existingObject(with:)` (mirror `affectedTaskIDs` :149-163); build a `DiagnosticEvent` (category `.data`, name `"<entity>.<op>"`, payload incl. `author`, `objectUUID`, `changedProps`, optional `position`) and `await diagnosticLog.log(...)`. Keep the pure diff core a `nonisolated static func` so XCTest can call it.

**Step 1 — failing test** (runs under `swift test` with a shared in-memory container — same-coordinator, two contexts is allowed):
```swift
func test_observer_emits_position_update_with_author_on_reorder() async throws {
    let persistence = try await PersistenceController(configuration: .inMemory)
    let spy = SpyDiagnosticSink()                       // collects DiagnosticEvents
    let observer = DiagnosticHistoryObserver(persistence: persistence, tokenStore: .init(suiteName: "t.\(UUID())"), sink: spy)
    let store = TaskStore(persistence: persistence)
    let a = try await store.create(title: "a"); let b = try await store.create(title: "b")
    try await store.reorder(id: b, after: nil, before: a)   // moves b above a -> position write
    await observer.processPendingHistory()
    let events = await spy.events
    XCTAssertTrue(events.contains { $0.name == "LillistTask.update" && $0.payload["changedProps"]?.containsName("position") == true })
}
```
(Define `SpyDiagnosticSink` actor implementing the sink protocol the observer logs through — extract a tiny `protocol DiagnosticSink: Sendable { func log(_ event: DiagnosticEvent) async }` that both `DiagnosticLog` and the spy conform to, so the observer is testable without files.)

**Steps 2-4 — FAIL → implement → PASS.**

**Step 5 — commit:** `feat(diagnostics): persistent-history data-event observer`

### Task 9: Create-tie regression test (the bug class)

**Files:** `Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticTieAttributionTests.swift`

**Step 1 — test** (same-container, two contexts with **distinct authors**, interleaved to force equal tail positions — mirrors `TagStoreFindOrCreateRaceTests` shape): create two tasks via two contexts whose `nextPosition` both observe the same max → equal `position`; run the observer; assert the diagnostic events show two creates/position-writes with the **same position value** and **different authors**. This proves the feature captures the attribution the RCA said was missing. Mark with a comment that full cross-*process* attribution is signed-Mac/app-hosted only; this same-container variant runs in CI.

**Steps 2-5 — implement supporting hooks if needed → PASS → commit:** `test(diagnostics): regression — observer attributes a position tie to distinct authors`

---

## Phase 4 — Explicit semantic emits (stores)

### Task 10: `TaskStore` emits (create / reorder incl. throwing path / reparent)

**Files:** Modify `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`; tests `Packages/LillistCore/Tests/LillistCoreTests/Stores/TaskStoreDiagnosticEmitTests.swift`.

**Design:**
- Add `public var diagnosticLog: DiagnosticSink?` next to `breadcrumbs` (:21) + a fire-and-forget `emitDiag(_:)` helper mirroring `recordCrumb` (:32-36).
- `nextPosition` (:685): change to `-> (assigned: Double, observedMax: Double?)` (or add a sibling that returns the max) so `create` can log `observedMaxPosition`. Update the 2 callers (`create` :138, `reparent` :288).
- `create` (:138-147): capture `id`, `parentID`, `assignedPosition`, `observedMaxPosition` inside `perform`, emit `task.create` after the block (success) and in the catch (failure).
- `reorder` (:302-356): capture `afterID/beforeID/afterPosition/beforePosition/computedPosition/didRecompact` inside `perform`; emit `task.reorder` on success **and in the `catch`** with `threwError: true` + the captured anchor pair (capture values **before** the throw; do not touch the rolled-back context). This is the RCA path — the test must assert the emit fires on the `anchors out of order` throw.
- `reparent` (:271-298): emit `task.reparent` with `oldParentID/newParentID/assignedPosition` (event name `task.reparent`, NOT the `task.move` crumb verb).

**Step 1 — failing tests:** (a) `create` emits `task.create` with `assignedPosition` + `observedMaxPosition`; (b) a successful `reorder` emits `task.reorder` with the anchor pair + `threwError:false`; (c) **seed two siblings with equal positions** (via two-context tie or direct managed-object edit through a test seam) and assert `reorder` into that gap emits `task.reorder` with `threwError:true` and the equal anchor pair, even though it throws. Use a `SpyDiagnosticSink`.

**Steps 2-4 — FAIL → implement → PASS** (`swift test --package-path Packages/LillistCore --filter TaskStoreDiagnosticEmit`).

**Step 5 — commit:** `feat(diagnostics): emit task.create/reorder/reparent (incl. throwing reorder)`

### Task 11: `SmartFilterStore` emit (`filter.reorder`)

**Files:** Modify `SmartFilterStore.swift` (:262 reorder — add `diagnosticLog` property + do/catch wrapper + emit on success and throwing path); test `SmartFilterStoreDiagnosticEmitTests.swift`. Mirror Task 10. **Commit:** `feat(diagnostics): emit filter.reorder (incl. throwing path)`

---

## Phase 5 — Drag-layer emits (LillistUI)

### Task 12: `DragController` emits drag.start / coalesced drag.over / drag.drop

**Files:** Modify `Packages/LillistUI/Sources/LillistUI/DragReorder/DragController.swift`; test `Packages/LillistUI/Tests/LillistUITests/DragReorder/DragControllerDiagnosticTests.swift`.

**Design:** LillistUI depends on LillistCore, so `DragController` can hold `public var diagnosticLog: DiagnosticSink?` and emit directly (non-blocking `Task { await log.log(...) }` since `DragController` is `@MainActor`). Emit:
- `drag.start` in `beginDrag` (:84) after the `.idle` guard — payload `draggedID`, `sourceIndex` (index of `draggedID` in `flatRows`).
- `drag.over` in `setResolvedTarget` (:118) — naturally coalesced (only called when the modifier detects a target change). Payload: resolved `DragTarget` summary (`highlightTargetID`, kind).
- `drag.drop` in `endDrag` (:137) — payload `draggedID`, final `target` (incl. `.rejected`/`.none` so cancelled drags are visible). Emit before the early `case .between/.onto` handler dispatch so rejected drops are captured.

**Step 1 — failing test:** inject a `SpyDiagnosticSink`; drive `beginDrag` → `setResolvedTarget(.between(...))` → `setResolvedTarget(.between(...))` (same target) → `endDrag`; assert exactly one `drag.start`, the right number of `drag.over` (the controller test can assert per `setResolvedTarget` call — the *coalescing* lives in the modifier's `if resolved != previous` guard, so document that and test the modifier-level coalescing separately if feasible, else assert controller emits 1:1 with `setResolvedTarget`), and one `drag.drop`. Mirror existing `DragControllerStateMachineTests`.

**Steps 2-5 — FAIL → implement → PASS → commit:** `feat(diagnostics): drag.start/over/drop emits via DragController`

---

## Phase 6 — Package export (`DiagnosticPackageBuilder`)

### Task 13: Builder — merge logs + manifest + zip (logs-only path first)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/Diagnostics/DiagnosticPackageBuilder.swift`
- Test: `Packages/LillistCore/Tests/LillistCoreTests/Diagnostics/DiagnosticPackageBuilderTests.swift`

**Design** (mirror `Export/Exporter.swift` stage-then-write + `CrashReport` manifest metadata):
```swift
public struct DiagnosticPackageBuilder: Sendable {
    public struct Options: Sendable {
        public var includeLogs: Bool
        public var includeStore: Bool
        public init(includeLogs: Bool, includeStore: Bool) { self.includeLogs = includeLogs; self.includeStore = includeStore }
    }
    public struct Metadata: Codable, Sendable {     // -> manifest.json
        public let buildVersion: String; public let osVersion: String; public let deviceModel: String
        public let exportedAt: Date; public let diagnosticLoggingEnabled: Bool; public let files: [String]
        public init(...)
    }
    // diagnosticsDir = App-Group/Lillist/Diagnostics ; storeURL = AppEnvironment.storeURL (nil for in-memory)
    public init(diagnosticsDir: URL?, storeURL: URL?, metadata: ... )
    public func build(options: Options) async throws -> URL   // returns a temp .zip URL
}
```
`build`: create temp `stage/`; if `includeLogs`, copy each `diag-*.jsonl` and write `events.jsonl` (merge all events, sort by `at` then `seq`) + `manifest.json` (JSONEncoder `.prettyPrinted,.sortedKeys`); zip `stage/` via `NSFileCoordinator().coordinate(readingItemAt: stage, options: .forUploading) { zipURL in copy out to a stable temp `.zip` }`; return the copied zip URL. Clean up `stage/`.

**Step 1 — failing tests (logs-only):** seed a temp diagnostics dir with two `diag-*.jsonl` files; `build(.init(includeLogs:true, includeStore:false))`; unzip (via `NSFileCoordinator(.forUploading)` is one-way — for the test, instead assert the returned URL is a `.zip` that exists and is non-empty, and separately unit-test the **merge** helper directly: `DiagnosticPackageBuilder.mergeEvents(from:)` returns events sorted by `at`+`seq`). Test `manifest` JSON contains the file inventory. Test cleanup (stage dir removed).

**Steps 2-5 — FAIL → implement → PASS → commit:** `feat(diagnostics): package builder — merge logs + manifest + zip`

### Task 14: Consistent SQLite snapshot (`VACUUM INTO`) + store-include path

**Files:** Modify `DiagnosticPackageBuilder.swift` (add the snapshot step); test additions.

**Design:** add `func snapshotStore(at storeURL: URL, into dest: URL) throws` using `import SQLite3`: open read-only (`sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)`), `sqlite3_exec(db, "VACUUM INTO '<dest>'", ...)`, close. Produces one consistent file incl. WAL contents — no need to copy `-wal`/`-shm`. In `build`, when `includeStore && storeURL != nil`, snapshot into `stage/store/Lillist.sqlite`. When `storeURL == nil` (in-memory/tests), skip with a `manifest` note.

**Step 1 — failing test:** build an on-disk store via `StoreConfiguration.onDisk(url:)` in a temp dir, create 3 tasks, then `snapshotStore` into a dest; open the dest with a fresh `NSPersistentContainer`/`NSPersistentStoreCoordinator` and assert it loads and the `LillistTask` count == 3. (This validates the snapshot is a complete, openable DB.)

**Steps 2-5 — FAIL → implement → PASS → commit:** `feat(diagnostics): consistent VACUUM INTO store snapshot in package`

---

## Phase 7 — Settings UI + wiring (both platforms)

> UI tasks are pattern-referenced (exact mirror points given); follow the cited files verbatim. Each task ends by building the relevant scheme without signing and (for iOS) adding/refreshing a tour snapshot.

### Task 15: iOS `DiagnosticsSection` + include sheet + `.fileExporter`

**Files:**
- Create: `Apps/Lillist-iOS/Sources/Settings/DiagnosticsSection.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/iOS/DiagnosticsIncludeSheet.swift` (pure presenter: two `@Binding` toggles + Create/Cancel closures — container/presenter rule, testable in the tour) **or** keep the sheet in-app if env coupling is unavoidable; prefer the LillistUI presenter for snapshot coverage.
- Modify: `Apps/Lillist-iOS/Sources/Settings/SettingsTab.swift:23` — insert `DiagnosticsSection()` between `CrashReportingSection(prefs: b)` and `AdvancedSection()`.
- Test: add a tour case to `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` (mirror `test_08_settings` :281) rendering the include sheet with mock bindings.

**Design (mirror `CrashReportingSection` + `AdvancedSection`):**
- `@Environment(AppEnvironment.self) private var environment`; `@State private var enabled = false`; `.task { enabled = await environment.devicePreferences.diagnosticLoggingEnabled() }`.
- `Section("Diagnostics") { Toggle("Diagnostic logging", isOn: $enabled).onChange { new in Task { await environment.devicePreferences.setDiagnosticLoggingEnabled(new); await environment.diagnosticLog?.setEnabled(new) } }; Text(footnote).font(.footnote).foregroundStyle(.secondary); Button("Prepare diagnostic package…") { showInclude = true } }`.
- `.sheet(isPresented: $showInclude)` → `DiagnosticsIncludeSheet(includeLogs:$includeLogs, includeStore:$includeStore, onCreate: { Task { await prepare() } }, onCancel: { showInclude = false })`.
- `prepare()` (mirror `AdvancedSection.runExport` :66-83, with a spinner): build via `DiagnosticPackageBuilder` off-main, set `exportURL`, present `.fileExporter(isPresented:document:contentType:defaultFilename:)` with a small `FileDocument` wrapping the zip (`UTType.zip`), and surface errors as a footnote (no crash). Clean up temp after export completes.

**Steps:** write the tour snapshot test (RED: new baseline), implement, build iOS scheme without signing (`xcodebuild ... CODE_SIGNING_ALLOWED=NO build`), record the snapshot on the signed Mac. **Commit:** `feat(diagnostics): iOS Settings diagnostics section + package export`

### Task 16: macOS `DiagnosticsPane`

**Files:** Create `Apps/Lillist-macOS/Sources/Preferences/DiagnosticsPane.swift` (mirror `CrashReportingPane` + `QuickCapturePane`; `Form { … }.formStyle(.grouped).fixedSize().task { await subscribe() }`); modify `Apps/Lillist-macOS/Sources/Preferences/PreferencesWindow.swift:22` to add `DiagnosticsPane().tabItem { Label("Diagnostics", systemImage: "stethoscope") }`. Same toggle (device prefs) + include + `.fileExporter` flow. Build macOS scheme without signing. **Commit:** `feat(diagnostics): macOS Diagnostics preferences pane`

### Task 17: Wire `DiagnosticLog` + observer + authors into both AppEnvironments + extensions

**Files:** Modify `Apps/Lillist-iOS/Sources/App/AppEnvironment.swift` (~:179-201 wiring, :243 appGroupID, :156-165 observer, :309-312 bootstrap), `Apps/Lillist-macOS/Sources/AppEnvironment.swift` (analogous, net-new observer), `Extensions/ShareExtension-iOS/ShareRootView.swift` (:77-83), `Extensions/ShortcutsActions/IntentSupport.swift` (:73-82) + `AddTaskIntent.swift:25`.

**Design:**
- Expose `let diagnosticLog: DiagnosticLog` on AppEnvironment, built as `DiagnosticLog.shared(process: .app /* .macApp */, appGroupID: Self.appGroupID, enabled: await devicePreferences.diagnosticLoggingEnabled())`.
- Inject into stores beside breadcrumbs: `taskStore.diagnosticLog = diagnosticLog; smartFilterStore.diagnosticLog = diagnosticLog`.
- Construct `DiagnosticHistoryObserver` with its own token store key + sink = `diagnosticLog`; `await observer.processPendingHistory(); observer.start()` in `bootstrap()` (net-new on macOS).
- Inject into `DragController`: in `TasksView`/`TaskListView` `.onAppear` (alongside `setOnDrop`) set `dragController.diagnosticLog = env.diagnosticLog`.
- Extensions: build their `PersistenceController` with the distinct author (`.shareExtension` / `.appIntents`) via the `GatedPersistenceResolver` author param (Task 7), construct a process-scoped `DiagnosticLog.shared(process:.shareExtension/.appIntents, appGroupID:, enabled: DevicePreferencesStore(appGroupID:).diagnosticLoggingEnabled())`, and assign to their `TaskStore.diagnosticLog`.

**Tests:** these are wiring; covered by build + the app-hosted attribution test (signed Mac). Build both schemes without signing. **Commit:** `feat(diagnostics): wire DiagnosticLog + history observer + per-process authors`

---

## Phase 8 — Localization, project regen, verification

### Task 18: Localize new strings across all three catalogs
Add every new user-visible string (section/pane title, toggle label + footnote, "Prepare diagnostic package…", include-sheet labels "Diagnostic logs"/"Copy of data store"/"Create"/"Cancel", export error text) to **all three** `Localizable.xcstrings` (`Apps/Lillist-iOS/Resources`, `Apps/Lillist-macOS/Resources`, `Packages/LillistUI/Sources/LillistUI/Resources`). Run `Tools/CI/check-lillistui-localization.sh` → expect PASS. **Commit:** `feat(loc): diagnostic-logging strings across iOS/macOS/LillistUI`

### Task 19: Regenerate pbxprojs
New **app-target** files were added (`DiagnosticsSection.swift`, `DiagnosticsPane.swift`, new app-target test files). Run:
```bash
(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
(cd Apps && xcodegen generate --spec project.yml --project .)
git diff --stat   # expect only the two .pbxproj files
```
**Commit:** `build(diagnostics): regenerate pbxproj for new app-target files`

### Task 20: Full verification
Run the matrix:
```bash
swift test --package-path Packages/LillistCore --parallel --num-workers 2
swift test --package-path Packages/LillistUI --skip Snapshot --skip Tour
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```
On the signed Mac, run the app-hosted/snapshot suites (`-scheme Lillist-iOS` full) including the new tour case and (if present) the live attribution test. Treat any warning as an error (fix at the architecture level). Update `docs/engineering-notes.md` with one entry if a non-obvious gotcha surfaced (e.g. the per-process author change interacting with the reconciler). **Commit:** `test(diagnostics): full matrix green` (+ notes entry if warranted).

---

## Done-when
- Toggling "Diagnostic logging" in iOS Settings and macOS Preferences flips logging on both platforms; default is on in Debug/TestFlight, off in Release.
- Reorders, creates, reparents, drags, and all data mutations (incl. extension- and CloudKit-authored, attributed by process) append to `App-Group/Lillist/Diagnostics/diag-<day>-<process>.jsonl`, rolling 30 days, never blocking the UI.
- "Prepare diagnostic package…" → choose logs and/or data store → Files browser → a `.zip` containing merged + raw JSONL, `manifest.json`, and (optionally) a consistent `VACUUM INTO` store snapshot.
- All unit tests green under `swift test`; build matrix green; new strings localized in all three catalogs; pbxprojs regenerated.
- A reproduced position tie shows in the logs as equal `assignedPosition` with **distinct** `transactionAuthor` — the attribution the RCA flagged as missing.
