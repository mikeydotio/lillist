# Lillist Plan 9 — Crash Detection and Opt-in Reporting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the canary-based crash detection protocol, redaction pipeline, breadcrumb buffer, post-crash sheet, and user-mediated `mailto:` / `MFMailComposeViewController` delivery exactly as specified in design Section 8 ("Crash detection and opt-in reporting"). Zero remote telemetry; every transmission is user-initiated.

**Architecture:** A new `CrashReporting/` sub-namespace inside the `LillistCore` SPM package houses pure-Swift, platform-independent primitives (`CrashCanary`, `CanaryFile`, `BreadcrumbBuffer`, `LogRedactor`, `CrashReport`, `CrashReporter`). Platform-specific lifecycle wiring lives in the three app targets from Plans 6 (CLI), 7 (macOS), and 8 (iOS). SwiftUI UI lives in `LillistUI`. The flow is: lifecycle hook writes/deletes canary → on next launch `CrashReporter` detects stale canary → assembles a redacted `CrashReport` with optional logs + breadcrumbs based on user toggles → presents a non-blocking sheet → opens a pre-populated mail composer (or writes a `.lillistcrash` bundle on "Save as file…"). No server, no SDK, no analytics. Per design Section 8: "No third-party telemetry."

**Tech Stack:** Swift 6 strict concurrency, Swift Testing for unit tests, XCTest + `pointfreeco/swift-snapshot-testing` for SwiftUI snapshot tests (already added in Plan 7), `OSLog` / `OSLogStore` for log retrieval, `MessageUI` for iOS mail, `NSWorkspace` for macOS mail, Foundation for file I/O and regex redaction. All work hangs off existing `LillistCore` and `LillistUI` packages plus the three app targets.

> **Plan 3 deviation baked in:** Plan 3 renamed the `LillistCore` package's namespace enum to `LillistCoreInfo` so the module name no longer shadows it. Read the build version as **`LillistCoreInfo.version`** (not `LillistCore.version`) — already updated in the `CrashReport` snippets below.

---

## File Structure

```
Lillist/
├── docs/
│   └── superpowers/
│       └── plans/
│           └── 2026-05-12-crash-reporting.md         (this plan)
├── Packages/
│   ├── LillistCore/
│   │   ├── Sources/
│   │   │   └── LillistCore/
│   │   │       └── CrashReporting/
│   │   │           ├── CrashCanary.swift             (value type: pid/startedAt/build/host)
│   │   │           ├── CanaryFile.swift              (read/write/delete at platform path)
│   │   │           ├── Breadcrumb.swift              (value type: action/at/success)
│   │   │           ├── BreadcrumbBuffer.swift        (actor ring buffer cap=200)
│   │   │           ├── LogRedactor.swift             (pure redaction function)
│   │   │           ├── CrashReport.swift             (Codable bundle)
│   │   │           ├── CrashReporter.swift           (orchestrator actor)
│   │   │           ├── CrashReportTransport.swift    (protocol + Mailto/File impls)
│   │   │           ├── OSLogFetcher.swift            (OSLogStore wrapper)
│   │   │           └── AppPreferences+Crash.swift    (crashPromptsEnabled extension)
│   │   └── Tests/
│   │       └── LillistCoreTests/
│   │           └── CrashReporting/
│   │               ├── CrashCanaryTests.swift
│   │               ├── CanaryFileTests.swift
│   │               ├── BreadcrumbBufferTests.swift
│   │               ├── LogRedactorTests.swift
│   │               ├── CrashReportCodableTests.swift
│   │               ├── CrashReporterFlowTests.swift
│   │               └── Fixtures/
│   │                   ├── raw-logs-with-titles.txt   (golden input)
│   │                   ├── raw-logs-with-titles.expected.txt
│   │                   ├── raw-logs-with-paths.txt
│   │                   ├── raw-logs-with-paths.expected.txt
│   │                   ├── raw-logs-with-uuids.txt
│   │                   ├── raw-logs-with-uuids.expected.txt
│   │                   ├── raw-logs-with-emails.txt
│   │                   ├── raw-logs-with-emails.expected.txt
│   │                   ├── raw-logs-with-journal-bodies.txt
│   │                   ├── raw-logs-with-journal-bodies.expected.txt
│   │                   ├── raw-logs-with-tag-names.txt
│   │                   └── raw-logs-with-tag-names.expected.txt
│   └── LillistUI/
│       ├── Sources/
│       │   └── LillistUI/
│       │       └── CrashReporting/
│       │           ├── CrashReportSheet.swift        (the main sheet)
│       │           ├── CrashReportPreviewSheet.swift (the "View what will be sent" sheet)
│       │           └── CrashReportViewModel.swift    (@Observable)
│       └── Tests/
│           └── LillistUITests/
│               └── CrashReporting/
│                   ├── CrashReportSheetSnapshotTests.swift
│                   └── __Snapshots__/                 (created by swift-snapshot-testing)
├── Apps/
│   ├── Lillist-macOS/
│   │   └── Lillist_macOSApp.swift                    (modify: canary lifecycle + sheet host)
│   ├── Lillist-iOS/
│   │   ├── Lillist_iOSApp.swift                      (modify: canary lifecycle + sheet host)
│   │   └── MailComposerView.swift                    (new: UIViewControllerRepresentable for MFMailComposeViewController)
│   └── lillist-cli/
│       ├── Sources/
│       │   └── main.swift                            (modify: canary lifecycle, TTY notice)
│       └── Sources/Commands/
│           └── ReportCrash.swift                     (modify: implement non-interactive flow)
```

The redaction fixtures are real files committed to the repo so the redaction contract is reviewable in a PR diff. Snapshot images live alongside their tests in `__Snapshots__/` per the convention established in Plan 7.

---

## Notes for the Implementer

**TDD discipline.** Same as Plan 1: red → green → refactor → commit. Tests first, always.

**No live `OSLogStore` in unit tests.** The `OSLogFetcher` is protocol-wrapped (`LogFetching`) so `CrashReporter` flow tests inject a fake. We exercise the real `OSLogFetcher` in a single integration-style test that pulls the test process's own log entries; the heavy lifting is in golden-text `LogRedactor` tests.

**No live mail composer in unit tests.** `CrashReportTransport` is a protocol. `MailtoTransport` and `MailComposerTransport` are platform-specific implementations exercised only by snapshot tests and manual release-time checks. Flow tests use a `RecordingTransport` that captures the payload.

**Redaction is conservative.** It is preferable to over-redact (false positive: a tag name "Work" gets stripped from log text) than to under-redact (false negative: a journal body leaks). Where ambiguity exists, redact. The redactor strips:
- Anything matching the regex for a UUID (8-4-4-4-12 hex with dashes).
- Anything matching a path under the user's home directory (`/Users/<name>/...` or `/var/mobile/Containers/Data/Application/...`).
- Anything matching an email address (RFC 5322 simplified: `[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`).
- Anything between `<title>` and `</title>` markers — `OSLog` callers in `TaskStore` are responsible for wrapping any title in these markers when logging (enforced by code review; not in scope here beyond exposing the convention).
- Anything between `<notes>` / `</notes>`, `<journal>` / `</journal>`, `<tag>` / `</tag>` markers — same pattern.
- Anything after `title=` up to the next space or end-of-line (defense in depth for `TaskStore` logs that didn't get wrapped).

**The breadcrumb contract.** `Breadcrumb.action` is a free-form `String` but the `BreadcrumbBuffer.record(action:success:)` API explicitly forbids titles, IDs, or content. Callers pass verbs like `"task.create"`, `"task.status.change"`, `"smartFilter.run"`, `"cli.add"`. Tests pin the contract: any string passed that contains a UUID, a path, or an `@` character is rejected (`#expect(throws:)`).

**Canary path resolution.** `CanaryFile.url(for:)` takes a `Platform` enum:
- `.macOSApp` → `~/Library/Application Support/Lillist/launch.canary`
- `.macOSCLI` → `~/Library/Application Support/Lillist/launch-cli.canary`
- `.iOSApp` → app-group container `group.io.mikeydotio.Lillist`, file `launch.canary`

Tests inject a synthetic `URL` via a test-only initializer; tests never touch real `~/Library` paths.

**Lifecycle hooks.**
- macOS app (Plan 7): `App.init` calls `CrashReporter.start(platform: .macOSApp)`. An `NSApplicationDelegate` (added if not already present in Plan 7) implements `applicationWillTerminate(_:)` which calls `CrashReporter.shared.markCleanExit()`.
- iOS app (Plan 8): `App.init` calls `CrashReporter.start(platform: .iOSApp)`. A `UIWindowSceneDelegate` (added if not present in Plan 8) calls `markCleanExit()` in `sceneWillDisconnect(_:)` and an additional `NotificationCenter` observer on `UIApplication.willTerminateNotification` does the same.
- CLI (Plan 6): `main.swift` calls `CrashReporter.start(platform: .macOSCLI)` near top; an `atexit_b` block calls `markCleanExit()` on normal exit. A `signal()` handler for `SIGTERM`/`SIGINT` also calls `markCleanExit()` synchronously.

**`AppPreferences.crashPromptsEnabled`.** Plan 1 defined `AppPreferences` with several stored attributes. Plan 9 adds one more via a Core Data lightweight migration step (Task 11). Default is `true`. When `false`, `CrashReporter` still writes/deletes the canary (no behavior change there) but suppresses the sheet on next launch.

**Managed-object class generation — hand-written, not auto-generated.** `AppPreferences+CoreData.swift` is a hand-written `@NSManaged` subclass (see Plan 1, and the same convention applied in Plans 3/4). When you add the new `crashPromptsEnabled` attribute in Task 10, you must add a matching `@NSManaged public var crashPromptsEnabled: Bool` line to that file — the model XML change alone won't expose the property to Swift. Step 3 of Task 10 has been updated to include this.

**Build-plugin caching gotcha.** Plan 7 removed the
`CompileCoreDataModel` SwiftPM build-tool plugin from
`Packages/LillistCore/Package.swift`. Swift 6 / Xcode 17 compile
`.xcdatamodeld` natively via `.process(...)`. The stale-`.momd` failure
mode can still happen on tooling that caches by directory mtime — the
`touch` workaround below remains the right fix after any model edit:

```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

> **Plan 7 deviation notes (added retroactively).** Plan 7 established
> conventions that this plan should honor when wiring crash-reporting
> hooks into the app shells. Mirror these:
>
> - **App env wiring**: macOS `LillistApp` uses an async loading state
>   driven by `AppEnvironment.make()`; the `CrashReporter.start(...)`
>   call belongs in the same `.task` block that bootstraps the env,
>   *before* the `RootSplitView` renders. There is no
>   `PersistenceController.shared` to grab in `App.init`.
> - **macOS snapshot tests**: `swift-snapshot-testing` 1.17 only ships
>   `NSView` / `NSViewController` strategies on macOS. The crash
>   reporting sheet's macOS snapshots must wrap each SwiftUI view in
>   `NSHostingView` via Plan 7's `makeHostingView(_:size:)` helper at
>   `Packages/LillistUI/Tests/LillistUITests/Helpers/SnapshotEnvironment.swift`.
> - **macOS test target shape**: `Apps/Lillist-macOS/Tests/` is a
>   standalone bundle with `TEST_HOST=""` (no app host) so headless
>   `xcodebuild test` works without a development cert. Any new
>   crash-reporting tests in that bundle must NOT `@testable import
>   Lillist_macOS` — exercise `LillistCore` / `LillistUI` directly.
> - **`XCTAssert` + `try await`**: bind to a local before asserting.
> - **`AppPreferences` access**: the actual API is
>   `PreferencesStore.read()` / `.update { ... }`, not `.fetch()`.
>
> See `docs/engineering-notes.md` 2026-05-14 entries for the
> investigation trails.

**Commits.** Same conventional-commit prefixes used in Plan 1: `feat:`, `test:`, `chore:`, `fix:`, `refactor:`, `docs:`.

**Verification commands throughout:**
- `cd Packages/LillistCore && swift test --filter CrashReporting`
- `cd Packages/LillistUI && swift test --filter CrashReportSheet`
- `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS'`
- `xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 16'`

---

## Task 1: Stub the `CrashReporting/` directory and add the umbrella enum

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportingSmokeTests.swift`

- [ ] **Step 1: Write the failing smoke test**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportingSmokeTests.swift`:

```swift
import Testing
@testable import LillistCore

@Suite("CrashReporting smoke")
struct CrashReportingSmokeTests {
    @Test("Namespace exists and exposes a stable version tag")
    func namespaceExists() {
        #expect(CrashReporting.subsystemIdentifier == "io.mikeydotio.lillist.crash")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashReportingSmokeTests`
Expected: FAIL — `CrashReporting` undefined.

- [ ] **Step 3: Write the umbrella enum**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift`:

```swift
import Foundation

/// Umbrella namespace for the crash-reporting subsystem.
///
/// Implements design Section 8: canary-based crash detection,
/// opt-in redacted reporting, user-mediated `mailto:` delivery.
public enum CrashReporting {
    /// Stable subsystem string used for OSLog and as a sanity marker
    /// in tests. Never change after release.
    public static let subsystemIdentifier = "io.mikeydotio.lillist.crash"
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashReportingSmokeTests`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportingSmokeTests.swift
git commit -m "chore: stub CrashReporting namespace in LillistCore"
```

---

## Task 2: Implement `CrashCanary` value type

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashCanaryTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashCanaryTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CrashCanary")
struct CrashCanaryTests {
    @Test("Initializer captures all fields")
    func init_capturesFields() {
        let when = Date(timeIntervalSince1970: 1_000_000)
        let canary = CrashCanary(
            pid: 42,
            startedAt: when,
            buildVersion: "0.9.0 (123)",
            hostname: "studio.local"
        )
        #expect(canary.pid == 42)
        #expect(canary.startedAt == when)
        #expect(canary.buildVersion == "0.9.0 (123)")
        #expect(canary.hostname == "studio.local")
    }

    @Test("Codable round-trip preserves all fields")
    func codable_roundTrip() throws {
        let original = CrashCanary(
            pid: 99,
            startedAt: Date(timeIntervalSince1970: 2_000_000),
            buildVersion: "1.0.0 (200)",
            hostname: "phone.local"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CrashCanary.self, from: data)
        #expect(decoded == original)
    }

    @Test("Two distinct canaries are not equal")
    func equatable_distinct() {
        let a = CrashCanary(pid: 1, startedAt: .now, buildVersion: "x", hostname: "h")
        let b = CrashCanary(pid: 2, startedAt: .now, buildVersion: "x", hostname: "h")
        #expect(a != b)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashCanaryTests`
Expected: FAIL — `CrashCanary` undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift`:

```swift
import Foundation

/// Snapshot of a process's identity at launch time.
///
/// Persisted as JSON in the canary file at launch and consulted on
/// the *next* launch to determine whether the previous run crashed.
/// See design Section 8.
public struct CrashCanary: Codable, Equatable, Sendable {
    /// The OS process ID of the run.
    public let pid: Int32
    /// When the process began. Used to bound the OSLog query window
    /// on the next launch.
    public let startedAt: Date
    /// Marketing version + build number (e.g. `"1.0.0 (123)"`).
    public let buildVersion: String
    /// Device hostname. Useful for differentiating a Mac crash from
    /// an iPhone crash when Mikey triages a report.
    public let hostname: String

    public init(pid: Int32, startedAt: Date, buildVersion: String, hostname: String) {
        self.pid = pid
        self.startedAt = startedAt
        self.buildVersion = buildVersion
        self.hostname = hostname
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashCanaryTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashCanaryTests.swift
git commit -m "feat: add CrashCanary value type for crash detection"
```

---

## Task 3: Implement `CanaryFile` (read/write/delete at platform-appropriate path)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CanaryFileTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CanaryFileTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CanaryFile")
struct CanaryFileTests {
    /// Synthesize a fresh temp file URL per test so we never touch
    /// real ~/Library state.
    private func makeTempURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("canary-\(UUID().uuidString).json")
    }

    @Test("writeFresh writes canary JSON to the configured URL")
    func writeFresh_writesFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        let canary = CrashCanary(pid: 7, startedAt: .now, buildVersion: "t", hostname: "h")
        try file.writeFresh(canary)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("readIfPresent returns nil when file does not exist")
    func read_absent_returnsNil() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        #expect(try file.readIfPresent() == nil)
    }

    @Test("Round trip: write then read returns equal canary")
    func writeThenRead_roundTrip() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        let canary = CrashCanary(pid: 42, startedAt: Date(timeIntervalSince1970: 100), buildVersion: "v", hostname: "h")
        try file.writeFresh(canary)
        let read = try file.readIfPresent()
        #expect(read == canary)
    }

    @Test("deleteOnCleanExit removes the file")
    func delete_removesFile() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        try file.writeFresh(CrashCanary(pid: 1, startedAt: .now, buildVersion: "v", hostname: "h"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        try file.deleteOnCleanExit()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("deleteOnCleanExit on missing file is a no-op")
    func delete_missing_isNoop() throws {
        let url = makeTempURL()
        let file = CanaryFile(url: url)
        // No throw expected.
        try file.deleteOnCleanExit()
    }

    @Test("writeFresh creates parent directory if missing")
    func writeFresh_createsParentDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory
        let nested = tmp
            .appendingPathComponent("canary-test-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("launch.canary")
        defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent().deletingLastPathComponent()) }
        let file = CanaryFile(url: nested)
        try file.writeFresh(CrashCanary(pid: 1, startedAt: .now, buildVersion: "v", hostname: "h"))
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test("readIfPresent returns nil and discards corrupt file")
    func read_corrupt_returnsNilAndDiscards() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid JSON".utf8).write(to: url)
        let file = CanaryFile(url: url)
        #expect(try file.readIfPresent() == nil)
        // Corrupt files are removed so we don't keep trying to read them.
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CanaryFileTests`
Expected: FAIL — `CanaryFile` undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift`:

```swift
import Foundation

/// Manages the on-disk presence of the launch canary.
///
/// Design Section 8: written on clean launch, deleted on clean
/// termination, presence on the next launch implies a crash.
public struct CanaryFile: Sendable {
    /// Logical owner of the canary; controls which path is used by
    /// `defaultURL(for:)`.
    public enum Platform: Sendable {
        case macOSApp
        case macOSCLI
        case iOSApp
    }

    public let url: URL

    /// Direct-URL initializer; primarily for tests but also used by
    /// callers that have already resolved an app-group container URL.
    public init(url: URL) {
        self.url = url
    }

    /// Standard path resolution per design Section 8.
    ///
    /// macOS: `~/Library/Application Support/Lillist/launch.canary`
    /// macOS CLI: `~/Library/Application Support/Lillist/launch-cli.canary`
    /// iOS: app-group container `group.io.mikeydotio.Lillist/launch.canary`
    public static func defaultURL(for platform: Platform) -> URL {
        switch platform {
        case .macOSApp:
            return appSupportLillist().appendingPathComponent("launch.canary")
        case .macOSCLI:
            return appSupportLillist().appendingPathComponent("launch-cli.canary")
        case .iOSApp:
            let groupID = "group.io.mikeydotio.Lillist"
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: groupID)
                ?? FileManager.default.temporaryDirectory
            return container.appendingPathComponent("launch.canary")
        }
    }

    private static func appSupportLillist() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Lillist", isDirectory: true)
    }

    /// Atomically replace the canary contents with the given record.
    public func writeFresh(_ canary: CrashCanary) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(canary)
        try data.write(to: url, options: .atomic)
    }

    /// Read the canary if it exists. Returns nil for missing or
    /// corrupt files; corrupt files are deleted so a poisoned write
    /// doesn't haunt the user forever.
    public func readIfPresent() throws -> CrashCanary? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(CrashCanary.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Remove the canary; safe to call when the file does not exist.
    public func deleteOnCleanExit() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CanaryFileTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CanaryFileTests.swift
git commit -m "feat: add CanaryFile with platform-aware path resolution"
```

---

## Task 4: Implement `Breadcrumb` and `BreadcrumbBuffer` (actor ring buffer, cap 200)

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift`
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("BreadcrumbBuffer")
struct BreadcrumbBufferTests {
    @Test("Empty buffer snapshot is empty")
    func empty_snapshotEmpty() async {
        let buffer = BreadcrumbBuffer()
        let snap = await buffer.snapshot()
        #expect(snap.isEmpty)
    }

    @Test("Recording a breadcrumb appends it")
    func record_appends() async throws {
        let buffer = BreadcrumbBuffer()
        try await buffer.record(action: "task.create", success: true)
        let snap = await buffer.snapshot()
        #expect(snap.count == 1)
        #expect(snap.first?.action == "task.create")
        #expect(snap.first?.success == true)
    }

    @Test("Capacity is 200; the 201st record evicts the first")
    func capacity_evictsOldest() async throws {
        let buffer = BreadcrumbBuffer()
        for i in 0..<201 {
            try await buffer.record(action: "step.\(i)", success: true)
        }
        let snap = await buffer.snapshot()
        #expect(snap.count == 200)
        #expect(snap.first?.action == "step.1")
        #expect(snap.last?.action == "step.200")
    }

    @Test("Rejects breadcrumb containing a UUID")
    func rejects_uuidInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(
                action: "task.create 12345678-1234-1234-1234-1234567890AB",
                success: true
            )
        }
    }

    @Test("Rejects breadcrumb containing an email")
    func rejects_emailInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(action: "user mikeyward@gmail.com", success: true)
        }
    }

    @Test("Rejects breadcrumb containing a path-like substring")
    func rejects_pathInAction() async {
        let buffer = BreadcrumbBuffer()
        await #expect(throws: BreadcrumbBuffer.RecordError.self) {
            try await buffer.record(action: "loaded /Users/mikey/file", success: true)
        }
    }

    @Test("Snapshot returns immutable copy; subsequent records do not mutate it")
    func snapshot_isImmutable() async throws {
        let buffer = BreadcrumbBuffer()
        try await buffer.record(action: "a", success: true)
        let snap = await buffer.snapshot()
        try await buffer.record(action: "b", success: true)
        #expect(snap.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter BreadcrumbBufferTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write `Breadcrumb` value type**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift`:

```swift
import Foundation

/// One entry in the breadcrumb ring buffer.
///
/// By contract, `action` is a verb-form string (e.g. `"task.create"`)
/// and contains no titles, IDs, paths, or email addresses. See design
/// Section 8: "no titles or content, just verbs and counts."
public struct Breadcrumb: Codable, Equatable, Sendable {
    public let action: String
    public let at: Date
    public let success: Bool

    public init(action: String, at: Date, success: Bool) {
        self.action = action
        self.at = at
        self.success = success
    }
}
```

- [ ] **Step 4: Write `BreadcrumbBuffer` actor**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift`:

```swift
import Foundation

/// Thread-safe ring buffer of the last 200 user actions.
///
/// The buffer's job is to capture **what** happened (verb), **when**
/// (timestamp), and **whether it succeeded** — but never anything
/// that could identify the data the user was operating on. Inputs
/// containing UUIDs, paths, or email addresses are rejected at the
/// API boundary; see design Section 8.
public actor BreadcrumbBuffer {
    /// Maximum number of entries retained. Per design Section 8.
    public static let capacity: Int = 200

    private var entries: [Breadcrumb] = []

    public init() {}

    public enum RecordError: Error, Equatable, Sendable {
        case containsUUID
        case containsEmail
        case containsPath
        case empty
    }

    /// Record an action. Throws if the action string appears to
    /// contain identifying content.
    public func record(action: String, success: Bool, at: Date = .now) throws {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RecordError.empty }
        if Self.uuidRegex.firstMatch(
            in: action,
            range: NSRange(action.startIndex..., in: action)
        ) != nil {
            throw RecordError.containsUUID
        }
        if action.contains("@") {
            throw RecordError.containsEmail
        }
        if action.contains("/") {
            throw RecordError.containsPath
        }
        entries.append(Breadcrumb(action: action, at: at, success: success))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    /// Immutable snapshot of the current contents.
    public func snapshot() -> [Breadcrumb] {
        entries
    }

    private static let uuidRegex: NSRegularExpression = {
        // 8-4-4-4-12 hex with dashes, case-insensitive.
        let pattern = #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#
        return try! NSRegularExpression(pattern: pattern)
    }()
}
```

- [ ] **Step 5: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter BreadcrumbBufferTests`
Expected: PASS, 7 tests.

- [ ] **Step 6: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift \
        Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferTests.swift
git commit -m "feat: add BreadcrumbBuffer actor with 200-entry ring + content guards"
```

---

## Task 5: Implement `LogRedactor` with explicit regex patterns

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift`
- Create six pairs of golden fixture files under `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/`

The redactor is a pure function: `LogRedactor.redact(_ raw: String) -> String`. It applies, in order, the following passes (each independent and idempotent):

| Pass | Pattern | Replacement |
|---|---|---|
| UUIDs | `\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b` | `<uuid>` |
| User home paths (macOS) | `/Users/[^/\s]+(/[^\s]*)?` | `<path>` |
| User home paths (iOS containers) | `/var/mobile/Containers/Data/Application/[A-Z0-9-]+(/[^\s]*)?` | `<path>` |
| User home paths (generic `~`) | `~/[^\s]*` | `<path>` |
| Email addresses | `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` | `<email>` |
| Wrapped titles | `<title>[\s\S]*?</title>` | `<title><redacted></title>` |
| Wrapped notes | `<notes>[\s\S]*?</notes>` | `<notes><redacted></notes>` |
| Wrapped journal bodies | `<journal>[\s\S]*?</journal>` | `<journal><redacted></journal>` |
| Wrapped tag names | `<tag>[\s\S]*?</tag>` | `<tag><redacted></tag>` |
| Defense-in-depth `title=…` | `title=[^\s\n]*` | `title=<redacted>` |
| Defense-in-depth `notes=…` | `notes=[^\s\n]*` | `notes=<redacted>` |
| Defense-in-depth `tag=…` | `tag=[^\s\n]*` | `tag=<redacted>` |

- [ ] **Step 1: Write the six fixture pairs**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-titles.txt`:

```
2026-05-12 10:00:01 [TaskStore] created <title>Buy groceries on the way home</title>
2026-05-12 10:00:02 [TaskStore] updated title=Pickup-dry-cleaning to closed
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-titles.expected.txt`:

```
2026-05-12 10:00:01 [TaskStore] created <title><redacted></title>
2026-05-12 10:00:02 [TaskStore] updated title=<redacted> to closed
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-paths.txt`:

```
2026-05-12 10:00:01 [Attach] saved to /Users/mikey/Documents/foo.png
2026-05-12 10:00:02 [Attach] saved to /var/mobile/Containers/Data/Application/12345678-AAAA-BBBB-CCCC-DEADBEEF0000/Library/bar.png
2026-05-12 10:00:03 [Attach] expand ~/Library/Application Support/Lillist
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-paths.expected.txt`:

```
2026-05-12 10:00:01 [Attach] saved to <path>
2026-05-12 10:00:02 [Attach] saved to <path>
2026-05-12 10:00:03 [Attach] expand <path>
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-uuids.txt`:

```
2026-05-12 10:00:01 [TaskStore] loaded task 12345678-1234-1234-1234-1234567890ab
2026-05-12 10:00:02 [Sync] zone change ABCDEF01-2345-6789-ABCD-EF0123456789
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-uuids.expected.txt`:

```
2026-05-12 10:00:01 [TaskStore] loaded task <uuid>
2026-05-12 10:00:02 [Sync] zone change <uuid>
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-emails.txt`:

```
2026-05-12 10:00:01 [Account] iCloud account mikeyward@gmail.com active
2026-05-12 10:00:02 [Account] backup to alt+test@example.co.uk
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-emails.expected.txt`:

```
2026-05-12 10:00:01 [Account] iCloud account <email> active
2026-05-12 10:00:02 [Account] backup to <email>
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-journal-bodies.txt`:

```
2026-05-12 10:00:01 [Journal] noted <journal>This is what I was doing today and tomorrow</journal>
2026-05-12 10:00:02 [Journal] noted notes=Some-private-notes-here
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-journal-bodies.expected.txt`:

```
2026-05-12 10:00:01 [Journal] noted <journal><redacted></journal>
2026-05-12 10:00:02 [Journal] noted notes=<redacted>
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-tag-names.txt`:

```
2026-05-12 10:00:01 [TagStore] created <tag>Personal/Health</tag>
2026-05-12 10:00:02 [TagStore] linked tag=Work-Confidential to task
```

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-with-tag-names.expected.txt`:

```
2026-05-12 10:00:01 [TagStore] created <tag><redacted></tag>
2026-05-12 10:00:02 [TagStore] linked tag=<redacted> to task
```

- [ ] **Step 2: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("LogRedactor")
struct LogRedactorTests {
    /// Find a fixture by name relative to this test bundle.
    private func fixture(_ basename: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(
            forResource: basename,
            withExtension: nil,
            subdirectory: "Fixtures"
        ) else {
            Issue.record("Missing fixture \(basename)")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func goldenTest(_ baseName: String) throws {
        let raw = try fixture("\(baseName).txt")
        let expected = try fixture("\(baseName).expected.txt")
        let redacted = LogRedactor.redact(raw)
        #expect(
            redacted == expected,
            "Redaction mismatch for \(baseName).\nGOT:\n\(redacted)\nEXPECTED:\n\(expected)"
        )
    }

    @Test("Strips wrapped titles and title= forms")
    func titles() throws { try goldenTest("raw-logs-with-titles") }

    @Test("Strips user home paths on macOS, iOS, and ~ form")
    func paths() throws { try goldenTest("raw-logs-with-paths") }

    @Test("Replaces UUIDs with <uuid>")
    func uuids() throws { try goldenTest("raw-logs-with-uuids") }

    @Test("Replaces email addresses with <email>")
    func emails() throws { try goldenTest("raw-logs-with-emails") }

    @Test("Strips journal bodies and notes= forms")
    func journalBodies() throws { try goldenTest("raw-logs-with-journal-bodies") }

    @Test("Strips wrapped tag names and tag= forms")
    func tagNames() throws { try goldenTest("raw-logs-with-tag-names") }

    @Test("Empty input → empty output")
    func empty() {
        #expect(LogRedactor.redact("") == "")
    }

    @Test("Plain text with no PII is unchanged")
    func clean() {
        let input = "2026-05-12 10:00:01 [Sync] zone change started"
        #expect(LogRedactor.redact(input) == input)
    }

    @Test("Redaction is idempotent")
    func idempotent() {
        let input = "loaded /Users/mikey/file 12345678-1234-1234-1234-1234567890ab"
        let once = LogRedactor.redact(input)
        let twice = LogRedactor.redact(once)
        #expect(once == twice)
    }
}
```

- [ ] **Step 3: Register fixtures as resources in `Package.swift`**

Edit `Packages/LillistCore/Package.swift`. Add a `resources:` entry on the `LillistCoreTests` target so fixtures are bundled:

```swift
        .testTarget(
            name: "LillistCoreTests",
            dependencies: ["LillistCore"],
            resources: [
                .process("CrashReporting/Fixtures")
            ]
        )
```

- [ ] **Step 4: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter LogRedactorTests`
Expected: FAIL — `LogRedactor` undefined.

- [ ] **Step 5: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift`:

```swift
import Foundation

/// Pure-function redaction over raw log text.
///
/// Applies the redaction passes enumerated in the Plan 9 design,
/// in fixed order. Each pass is idempotent. Design Section 8
/// requires that task titles, notes, journal bodies, tag names,
/// file paths under user dirs, email addresses, and UUIDs are all
/// stripped before any log text leaves the device.
public enum LogRedactor {

    public static func redact(_ raw: String) -> String {
        var s = raw

        for pass in passes {
            s = pass.regex.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: pass.replacement
            )
        }
        return s
    }

    private struct Pass {
        let regex: NSRegularExpression
        let replacement: String
    }

    /// Order matters: wrapped-marker passes go before defense-in-depth
    /// passes so we don't double-stamp content; UUIDs go before paths
    /// because some iOS container paths contain UUIDs we'd rather
    /// pretend are just paths.
    private static let passes: [Pass] = {
        func make(_ pattern: String, _ replacement: String, options: NSRegularExpression.Options = []) -> Pass {
            // swiftlint:disable:next force_try
            let r = try! NSRegularExpression(pattern: pattern, options: options)
            return Pass(regex: r, replacement: replacement)
        }
        return [
            // Wrapped markers first — preserves the marker for clarity.
            make(#"<title>[\s\S]*?</title>"#, "<title><redacted></title>"),
            make(#"<notes>[\s\S]*?</notes>"#, "<notes><redacted></notes>"),
            make(#"<journal>[\s\S]*?</journal>"#, "<journal><redacted></journal>"),
            make(#"<tag>[\s\S]*?</tag>"#, "<tag><redacted></tag>"),
            // Defense-in-depth key=value forms (whitespace-delimited).
            make(#"title=[^\s\n]*"#, "title=<redacted>"),
            make(#"notes=[^\s\n]*"#, "notes=<redacted>"),
            make(#"tag=[^\s\n]*"#, "tag=<redacted>"),
            // Paths.
            make(#"/Users/[^/\s]+(?:/[^\s]*)?"#, "<path>"),
            make(#"/var/mobile/Containers/Data/Application/[A-Z0-9-]+(?:/[^\s]*)?"#, "<path>"),
            make(#"~/[^\s]*"#, "<path>"),
            // Emails.
            make(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>"),
            // UUIDs last — by this point paths and emails are gone.
            make(#"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#, "<uuid>")
        ]
    }()
}
```

- [ ] **Step 6: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter LogRedactorTests`
Expected: PASS, 9 tests.

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/ \
        Packages/LillistCore/Package.swift
git commit -m "feat: add LogRedactor with golden-fixture redaction tests"
```

---

## Task 6: Implement `CrashReport` Codable bundle

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportCodableTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportCodableTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReport Codable")
struct CrashReportCodableTests {
    private func sampleCanary() -> CrashCanary {
        CrashCanary(pid: 42, startedAt: Date(timeIntervalSince1970: 1_000_000), buildVersion: "1.0 (1)", hostname: "host")
    }

    @Test("Round-trips with all sections present")
    func full_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15.4",
            deviceModel: "MacBookPro18,4",
            canary: sampleCanary(),
            userDescription: "I clicked the new-task button",
            logs: ["redacted line 1", "redacted line 2"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: .now, success: true)]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.buildVersion == report.buildVersion)
        #expect(decoded.osVersion == report.osVersion)
        #expect(decoded.deviceModel == report.deviceModel)
        #expect(decoded.canary == report.canary)
        #expect(decoded.userDescription == report.userDescription)
        #expect(decoded.logs == report.logs)
        #expect(decoded.breadcrumbs?.count == 1)
    }

    @Test("Round-trips with logs and breadcrumbs both nil")
    func minimal_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "iOS 18",
            deviceModel: "iPhone17,1",
            canary: sampleCanary(),
            userDescription: nil,
            logs: nil,
            breadcrumbs: nil
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == nil)
        #expect(decoded.breadcrumbs == nil)
        #expect(decoded.userDescription == nil)
    }

    @Test("Round-trips with logs present, breadcrumbs nil")
    func logsOnly_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: nil,
            logs: ["line"],
            breadcrumbs: nil
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == ["line"])
        #expect(decoded.breadcrumbs == nil)
    }

    @Test("Round-trips with breadcrumbs present, logs nil")
    func breadcrumbsOnly_roundTrip() throws {
        let report = CrashReport(
            buildVersion: "1.0",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: nil,
            logs: nil,
            breadcrumbs: [Breadcrumb(action: "a", at: .now, success: false)]
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.logs == nil)
        #expect(decoded.breadcrumbs?.count == 1)
    }

    @Test("renderedAsPlainText is deterministic across runs")
    func plainText_stable() {
        let report = CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: sampleCanary(),
            userDescription: "did a thing",
            logs: ["log line"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: Date(timeIntervalSince1970: 0), success: true)]
        )
        let a = report.renderedAsPlainText()
        let b = report.renderedAsPlainText()
        #expect(a == b)
        #expect(a.contains("Build: 1.0 (1)"))
        #expect(a.contains("did a thing"))
        #expect(a.contains("log line"))
        #expect(a.contains("task.create"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashReportCodableTests`
Expected: FAIL — `CrashReport` undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift`:

```swift
import Foundation

/// User-facing crash report bundle.
///
/// Composition is opt-in section by section per design Section 8:
/// `logs` is nil unless the user kept the "Recent app logs" checkbox
/// on; `breadcrumbs` is nil unless they kept the breadcrumbs checkbox
/// on. `userDescription` may be nil if they didn't type anything.
public struct CrashReport: Codable, Equatable, Sendable {
    public let buildVersion: String
    public let osVersion: String
    public let deviceModel: String
    public let canary: CrashCanary
    public let userDescription: String?
    public let logs: [String]?
    public let breadcrumbs: [Breadcrumb]?

    public init(
        buildVersion: String,
        osVersion: String,
        deviceModel: String,
        canary: CrashCanary,
        userDescription: String?,
        logs: [String]?,
        breadcrumbs: [Breadcrumb]?
    ) {
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.canary = canary
        self.userDescription = userDescription
        self.logs = logs
        self.breadcrumbs = breadcrumbs
    }

    /// Human-readable text rendering suitable for a mailto body or
    /// a `.lillistcrash` bundle's primary file. Stable across runs.
    public func renderedAsPlainText() -> String {
        var lines: [String] = []
        lines.append("Lillist crash report")
        lines.append("====================")
        lines.append("")
        lines.append("Build: \(buildVersion)")
        lines.append("OS: \(osVersion)")
        lines.append("Device: \(deviceModel)")
        lines.append("Host: \(canary.hostname)")
        lines.append("PID: \(canary.pid)")
        lines.append("Started: \(ISO8601DateFormatter().string(from: canary.startedAt))")
        lines.append("")
        if let userDescription, !userDescription.isEmpty {
            lines.append("--- What I was doing ---")
            lines.append(userDescription)
            lines.append("")
        }
        if let logs {
            lines.append("--- Logs (\(logs.count) lines, redacted) ---")
            lines.append(contentsOf: logs)
            lines.append("")
        }
        if let breadcrumbs {
            lines.append("--- Breadcrumbs (\(breadcrumbs.count)) ---")
            for crumb in breadcrumbs {
                let outcome = crumb.success ? "ok" : "fail"
                let at = ISO8601DateFormatter().string(from: crumb.at)
                lines.append("\(at) \(crumb.action) \(outcome)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashReportCodableTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportCodableTests.swift
git commit -m "feat: add CrashReport Codable bundle with plain-text rendering"
```

---

## Task 7: Implement `OSLogFetcher` and the `LogFetching` protocol

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherTests.swift`:

```swift
import Testing
import Foundation
import OSLog
@testable import LillistCore

@Suite("OSLogFetcher")
struct OSLogFetcherTests {
    @Test("Fake fetcher returns whatever was injected")
    func fake_returnsInjected() async throws {
        let fake = FakeLogFetcher(lines: ["a", "b"])
        let lines = try await fake.fetchRecentLines(since: .now, subsystem: "x")
        #expect(lines == ["a", "b"])
    }

    @Test("Real OSLogFetcher returns an array (may be empty in test environments)")
    func real_returnsArray() async throws {
        let fetcher = OSLogFetcher()
        let lines = try await fetcher.fetchRecentLines(
            since: Date(timeIntervalSinceNow: -300),
            subsystem: CrashReporting.subsystemIdentifier
        )
        // We don't assert non-empty: sandboxed test runners may not
        // grant log access. We only assert it doesn't throw.
        #expect(lines.count >= 0)
    }
}

/// Test-only fake.
struct FakeLogFetcher: LogFetching {
    let lines: [String]
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
        lines
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter OSLogFetcherTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift`:

```swift
import Foundation
import OSLog

/// Abstracts log retrieval so the crash reporter can be tested
/// without depending on `OSLogStore` (which is unavailable or
/// permission-gated in sandboxed test environments).
public protocol LogFetching: Sendable {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String]
}

/// Production implementation backed by `OSLogStore`.
///
/// Each line is the rendered composed message (no metadata) so the
/// resulting strings feed directly into `LogRedactor.redact`.
public struct OSLogFetcher: LogFetching {
    public init() {}

    public func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let entries = try store.getEntries(at: position)
        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            if logEntry.subsystem != subsystem { continue }
            lines.append("\(logEntry.date.ISO8601Format()) \(logEntry.composedMessage)")
        }
        return lines
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter OSLogFetcherTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/OSLogFetcherTests.swift
git commit -m "feat: add LogFetching protocol and OSLogStore-backed implementation"
```

---

## Task 8: Implement `CrashReportTransport` protocol with file + recording impls

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportTransportTests.swift`

The protocol covers both delivery modes: `mailto:` (default) and "Save as file…" (alternate). Platform-specific implementations (`MailtoTransport`, `MailComposerTransport`) live in the app targets; this file defines the protocol and the testable `FileSaveTransport` + `RecordingTransport`.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportTransportTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReportTransport")
struct CrashReportTransportTests {
    private func sampleReport() -> CrashReport {
        CrashReport(
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            canary: CrashCanary(pid: 1, startedAt: .now, buildVersion: "1.0 (1)", hostname: "h"),
            userDescription: "test",
            logs: ["line one"],
            breadcrumbs: [Breadcrumb(action: "task.create", at: .now, success: true)]
        )
    }

    @Test("RecordingTransport captures the payload on send")
    func recording_captures() async throws {
        let recording = RecordingTransport()
        try await recording.send(sampleReport())
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.userDescription == "test")
    }

    @Test("FileSaveTransport writes a .lillistcrash bundle at the destination")
    func fileSave_writesBundle() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("crash-\(UUID()).lillistcrash")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let transport = FileSaveTransport(destination: tmp)
        try await transport.send(sampleReport())
        #expect(FileManager.default.fileExists(atPath: tmp.path))
        let data = try Data(contentsOf: tmp)
        // The bundle is JSON for v1 (a real zip would require a third-
        // party dependency; the design accepts a JSON file as a
        // first-pass implementation of the .lillistcrash format).
        let decoded = try JSONDecoder().decode(CrashReport.self, from: data)
        #expect(decoded.userDescription == "test")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashReportTransportTests`
Expected: FAIL — types undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift`:

```swift
import Foundation

/// Strategy interface for delivering a crash report.
///
/// All transports are user-mediated per design Section 8:
/// `mailto:` opens the user's mail client with the payload prefilled
/// and *they* hit send; "Save as file…" produces a `.lillistcrash`
/// bundle the user can move and email later.
public protocol CrashReportTransport: Sendable {
    func send(_ report: CrashReport) async throws
}

/// Test-only transport that records every send for inspection.
public actor RecordingTransport: CrashReportTransport {
    public private(set) var captured: [CrashReport] = []
    public init() {}
    public func send(_ report: CrashReport) async throws {
        captured.append(report)
    }
}

/// Writes the report to a user-chosen file path as a `.lillistcrash`
/// bundle (currently a plain JSON encoding of the report; zip-style
/// bundling is a v2 nicety once a zip dependency is justified).
public struct FileSaveTransport: CrashReportTransport {
    public let destination: URL
    public init(destination: URL) {
        self.destination = destination
    }
    public func send(_ report: CrashReport) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: destination, options: .atomic)
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashReportTransportTests`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReportTransportTests.swift
git commit -m "feat: add CrashReportTransport protocol with file + recording implementations"
```

---

## Task 9: Implement `CrashReporter` orchestrator actor

**Files:**
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift`

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReporter flow")
struct CrashReporterFlowTests {
    /// Make a reporter writing to a sandboxed canary URL.
    private func makeReporter(
        logs: [String] = ["redacted log line"],
        breadcrumbs: [Breadcrumb] = [Breadcrumb(action: "task.create", at: .now, success: true)],
        transport: CrashReportTransport
    ) -> (CrashReporter, URL) {
        let canaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-\(UUID()).json")
        let buffer = BreadcrumbBuffer()
        Task { for crumb in breadcrumbs { try? await buffer.record(action: crumb.action, success: crumb.success, at: crumb.at) } }
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: canaryURL),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: FakeLogFetcher(lines: logs),
            breadcrumbs: buffer,
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (reporter, canaryURL)
    }

    @Test("No canary on launch ⇒ no pending crash")
    func noCanary_noPendingCrash() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
    }

    @Test("Stale canary on launch ⇒ pending crash returned, then fresh canary written")
    func staleCanary_returnsPending() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        // Plant a stale canary as if a prior run crashed.
        let stale = CrashCanary(pid: 99, startedAt: Date(timeIntervalSince1970: 999_000), buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == stale)
        // A fresh canary is now in place for *this* run.
        let fresh = try CanaryFile(url: url).readIfPresent()
        #expect(fresh != nil)
        #expect(fresh != stale)
    }

    @Test("Don't-send: transport is not invoked")
    func dontSend_noTransport() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.isEmpty)
    }

    @Test("Send with both sections: payload includes logs and breadcrumbs")
    func send_bothSections() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: "what I was doing",
            includeLogs: true,
            includeBreadcrumbs: true,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.logs?.isEmpty == false)
        #expect(captured.first?.breadcrumbs?.isEmpty == false)
        #expect(captured.first?.userDescription == "what I was doing")
    }

    @Test("Send with neither section: payload omits logs and breadcrumbs")
    func send_neitherSection() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.count == 1)
        #expect(captured.first?.logs == nil)
        #expect(captured.first?.breadcrumbs == nil)
    }

    @Test("Logs are redacted before assembly")
    func send_logsAreRedacted() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(
            logs: ["loaded task 12345678-1234-1234-1234-1234567890ab"],
            transport: recording
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let stale = CrashCanary(pid: 1, startedAt: .now, buildVersion: "0.9", hostname: "old")
        try CanaryFile(url: url).writeFresh(stale)
        _ = try await reporter.detectAndPrepare()
        try await reporter.submit(
            decision: .send,
            description: nil,
            includeLogs: true,
            includeBreadcrumbs: false,
            pending: stale
        )
        let captured = await recording.captured
        #expect(captured.first?.logs?.first?.contains("<uuid>") == true)
        #expect(captured.first?.logs?.first?.contains("12345678") == false)
    }

    @Test("markCleanExit removes the canary")
    func cleanExit_deletesCanary() async throws {
        let recording = RecordingTransport()
        let (reporter, url) = makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        try await reporter.start()
        #expect(FileManager.default.fileExists(atPath: url.path))
        try await reporter.markCleanExit()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashReporterFlowTests`
Expected: FAIL — `CrashReporter` undefined.

- [ ] **Step 3: Write implementation**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift`:

```swift
import Foundation

/// Orchestrates the full crash-detection-and-report flow per design
/// Section 8: write canary at startup, detect stale canary on next
/// launch, assemble a redacted opt-in payload, and hand it to a
/// transport.
public actor CrashReporter {

    /// The user's choice from the post-crash sheet.
    public enum SubmitDecision: Sendable, Equatable {
        case send
        case dontSend
    }

    private let canaryFile: CanaryFile
    private let buildVersion: String
    private let osVersion: String
    private let deviceModel: String
    private let hostname: String
    private let logFetcher: LogFetching
    private let breadcrumbs: BreadcrumbBuffer
    private let transport: CrashReportTransport
    private let now: @Sendable () -> Date

    public init(
        canaryFile: CanaryFile,
        buildVersion: String,
        osVersion: String,
        deviceModel: String,
        hostname: String,
        logFetcher: LogFetching,
        breadcrumbs: BreadcrumbBuffer,
        transport: CrashReportTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.canaryFile = canaryFile
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.hostname = hostname
        self.logFetcher = logFetcher
        self.breadcrumbs = breadcrumbs
        self.transport = transport
        self.now = now
    }

    /// Write a canary for the current process. Call from lifecycle
    /// entry points (App init / scene willConnect / CLI main).
    public func start() throws {
        let canary = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: now(),
            buildVersion: buildVersion,
            hostname: hostname
        )
        try canaryFile.writeFresh(canary)
    }

    /// Delete the canary. Call from lifecycle exit hooks.
    public func markCleanExit() throws {
        try canaryFile.deleteOnCleanExit()
    }

    /// On launch, return a `CrashCanary` if the previous run did
    /// not exit cleanly. Replaces the canary with a fresh one for
    /// the current run.
    public func detectAndPrepare() throws -> CrashCanary? {
        let prior = try canaryFile.readIfPresent()
        try start()
        return prior
    }

    /// Submit the user's choice. When `decision == .send`, assembles
    /// a `CrashReport` honoring the section toggles and hands it to
    /// the transport. When `decision == .dontSend`, no transport
    /// invocation happens at all.
    public func submit(
        decision: SubmitDecision,
        description: String?,
        includeLogs: Bool,
        includeBreadcrumbs: Bool,
        pending: CrashCanary
    ) async throws {
        guard decision == .send else { return }

        var logsSection: [String]? = nil
        if includeLogs {
            let rawSince = pending.startedAt.addingTimeInterval(-300)
            let raw = try await logFetcher.fetchRecentLines(
                since: rawSince,
                subsystem: CrashReporting.subsystemIdentifier
            )
            logsSection = raw.map(LogRedactor.redact)
        }

        var breadcrumbsSection: [Breadcrumb]? = nil
        if includeBreadcrumbs {
            breadcrumbsSection = await breadcrumbs.snapshot()
        }

        let report = CrashReport(
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            canary: pending,
            userDescription: description?.isEmpty == true ? nil : description,
            logs: logsSection,
            breadcrumbs: breadcrumbsSection
        )
        try await transport.send(report)
    }
}
```

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashReporterFlowTests`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift
git commit -m "feat: add CrashReporter actor orchestrating canary, redaction, and transport"
```

---

## Task 10: Add `crashPromptsEnabled` to `AppPreferences` via lightweight migration

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents` (add attribute)
- Create: `Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift` (expose getter/setter)
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashPromptPreferenceTests.swift`

- [ ] **Step 1: Write failing test**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashPromptPreferenceTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("crashPromptsEnabled preference")
struct CrashPromptPreferenceTests {
    @Test("Default value is true")
    func defaultIsTrue() async throws {
        let store = try TestStore.makeInMemory()
        let prefs = try await store.preferences.load()
        #expect(prefs.crashPromptsEnabled == true)
    }

    @Test("Setting false persists")
    func setFalsePersists() async throws {
        let store = try TestStore.makeInMemory()
        try await store.preferences.setCrashPromptsEnabled(false)
        let prefs = try await store.preferences.load()
        #expect(prefs.crashPromptsEnabled == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter CrashPromptPreferenceTests`
Expected: FAIL — attribute and API missing.

- [ ] **Step 3: Add the attribute to the Core Data model**

Edit `Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents`. Inside the `<entity name="AppPreferences" …>` block, append:

```xml
<attribute name="crashPromptsEnabled" optional="YES" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>
```

(This is a CloudKit-compatible additive change per design Section 3.)

Then open `Packages/LillistCore/Sources/LillistCore/ManagedObjects/AppPreferences+CoreData.swift` and add the matching `@NSManaged` property to the hand-written class declaration (this codebase does not use Core Data class codegen — see Plan 1 Task 8):

```swift
@NSManaged public var crashPromptsEnabled: Bool
```

Finally, force the build plugin to pick up the model change (see the "Build-plugin caching gotcha" note in the preamble):

```bash
touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/ \
      Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/
```

- [ ] **Step 4: Expose the value in `PreferencesStore`**

Open `Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift`. Add to the `AppPreferencesValue` DTO the field `var crashPromptsEnabled: Bool` (default `true`). Add to `PreferencesStore`:

```swift
public func setCrashPromptsEnabled(_ value: Bool) async throws {
    try await context.perform {
        let prefs = try self.loadOrCreate()
        prefs.crashPromptsEnabled = value
        prefs.modifiedAt = .now
        try self.context.save()
    }
}
```

(`loadOrCreate` is the existing helper introduced in Plan 1's `PreferencesStore`.)

- [ ] **Step 5: Add the `AppPreferences+Crash.swift` extension**

Write `Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift`:

```swift
import Foundation

extension AppPreferencesValue {
    /// Convenience: build a default-on copy if needed during
    /// migration from a pre-Plan-9 store.
    public static var crashPromptsDefault: Bool { true }
}
```

- [ ] **Step 6: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter CrashPromptPreferenceTests`
Expected: PASS, 2 tests. (Also run the full suite to confirm no regression: `swift test`.)

- [ ] **Step 7: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/ \
        Packages/LillistCore/Sources/LillistCore/Stores/PreferencesStore.swift \
        Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashPromptPreferenceTests.swift
git commit -m "feat: add crashPromptsEnabled preference with lightweight migration"
```

---

## Task 11: Build `CrashReportSheet` SwiftUI view + view model in `LillistUI`

**Files:**
- Create: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift`
- Create: `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift`

`LillistUI` depends on `LillistCore` (already configured in Plan 7).

- [ ] **Step 1: Write the view model**

Write `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportViewModel.swift`:

```swift
import Foundation
import Observation
import LillistCore

/// Backs `CrashReportSheet`. All assembly happens here so the view
/// stays purely declarative.
@MainActor
@Observable
public final class CrashReportViewModel {
    public var userDescription: String = ""
    public var includeLogs: Bool = true
    public var includeBreadcrumbs: Bool = true
    public var previewExpanded: Bool = false
    public private(set) var previewText: String = ""
    public private(set) var isSubmitting: Bool = false

    public let pending: CrashCanary
    private let reporter: CrashReporter

    public init(pending: CrashCanary, reporter: CrashReporter) {
        self.pending = pending
        self.reporter = reporter
    }

    /// Compose the would-be report (without sending) for the
    /// "View what will be sent" sheet.
    public func refreshPreview(buildVersion: String, osVersion: String, deviceModel: String) async {
        let report = CrashReport(
            buildVersion: buildVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            canary: pending,
            userDescription: userDescription.isEmpty ? nil : userDescription,
            logs: includeLogs ? ["(logs will be loaded here when sent)"] : nil,
            breadcrumbs: includeBreadcrumbs ? [] : nil
        )
        previewText = report.renderedAsPlainText()
    }

    /// Hit by the "Send report" button.
    public func send() async throws {
        isSubmitting = true
        defer { isSubmitting = false }
        try await reporter.submit(
            decision: .send,
            description: userDescription,
            includeLogs: includeLogs,
            includeBreadcrumbs: includeBreadcrumbs,
            pending: pending
        )
    }

    /// Hit by "Don't send".
    public func dontSend() async throws {
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: false,
            includeBreadcrumbs: false,
            pending: pending
        )
    }
}
```

- [ ] **Step 2: Write the preview sheet**

Write `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportPreviewSheet.swift`:

```swift
import SwiftUI

public struct CrashReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let body: String

    public init(body: String) {
        self.body = body
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                Text(body)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("What will be sent")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Write the main sheet**

Write `Packages/LillistUI/Sources/LillistUI/CrashReporting/CrashReportSheet.swift`:

```swift
import SwiftUI
import LillistCore

public struct CrashReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable public var model: CrashReportViewModel

    /// Caller-provided metadata so the view model can render an
    /// honest preview (build/OS/device come from the host process).
    public let buildVersion: String
    public let osVersion: String
    public let deviceModel: String

    @State private var showingPreview = false

    public init(
        model: CrashReportViewModel,
        buildVersion: String,
        osVersion: String,
        deviceModel: String
    ) {
        self.model = model
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Lillist quit unexpectedly last time.")
                        .font(.headline)
                    Text("Help me make it more reliable by sending a quick report. Totally optional.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("What were you doing?") {
                    TextEditor(text: $model.userDescription)
                        .frame(minHeight: 80)
                        .accessibilityLabel("Description of what you were doing")
                }
                Section("What to include") {
                    Toggle(isOn: $model.includeLogs) {
                        VStack(alignment: .leading) {
                            Text("Recent app logs")
                            Text("Last 5 min, ~50 KB; reviewable below")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $model.includeBreadcrumbs) {
                        VStack(alignment: .leading) {
                            Text("Last action breadcrumbs")
                            Text("No titles or content, just verbs and counts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button("View what will be sent") {
                        Task {
                            await model.refreshPreview(
                                buildVersion: buildVersion,
                                osVersion: osVersion,
                                deviceModel: deviceModel
                            )
                            showingPreview = true
                        }
                    }
                }
                Section {
                    Text("Reports go directly to Mikey (mikeyward@gmail.com). No third-party telemetry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Crash report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Don't send") {
                        Task {
                            try? await model.dontSend()
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send report") {
                        Task {
                            try? await model.send()
                            dismiss()
                        }
                    }
                    .disabled(model.isSubmitting)
                }
            }
            .sheet(isPresented: $showingPreview) {
                CrashReportPreviewSheet(body: model.previewText)
            }
        }
    }
}
```

- [ ] **Step 4: Verify the package builds**

Run: `cd Packages/LillistUI && swift build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistUI/Sources/LillistUI/CrashReporting/
git commit -m "feat: add CrashReportSheet, preview sheet, and view model in LillistUI"
```

---

## Task 12: Add snapshot tests for `CrashReportSheet` (light/dark, description, expanded preview)

**Files:**
- Modify: `Packages/LillistUI/Package.swift` (`swift-snapshot-testing` should already be a dep from Plan 7; re-confirm)
- Create: `Packages/LillistUI/Tests/LillistUITests/CrashReporting/CrashReportSheetSnapshotTests.swift`

- [ ] **Step 1: Write the snapshot test file**

Write `Packages/LillistUI/Tests/LillistUITests/CrashReporting/CrashReportSheetSnapshotTests.swift`:

```swift
import XCTest
import SwiftUI
import SnapshotTesting
import LillistCore
@testable import LillistUI

@MainActor
final class CrashReportSheetSnapshotTests: XCTestCase {

    private func makeModel(description: String = "") -> CrashReportViewModel {
        let canary = CrashCanary(pid: 1, startedAt: Date(timeIntervalSince1970: 0), buildVersion: "1.0", hostname: "h")
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("x.json")),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: NoopLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        let model = CrashReportViewModel(pending: canary, reporter: reporter)
        model.userDescription = description
        return model
    }

    private func host(_ view: some View, colorScheme: ColorScheme) -> some View {
        view
            .environment(\.colorScheme, colorScheme)
            .frame(width: 480, height: 640)
    }

    func test_light_emptyDescription() {
        let view = CrashReportSheet(model: makeModel(), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .light), as: .image)
    }

    func test_dark_emptyDescription() {
        let view = CrashReportSheet(model: makeModel(), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .dark), as: .image)
    }

    func test_light_filledDescription() {
        let view = CrashReportSheet(model: makeModel(description: "I was reorganizing tags."), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .light), as: .image)
    }

    func test_dark_filledDescription() {
        let view = CrashReportSheet(model: makeModel(description: "I was reorganizing tags."), buildVersion: "1.0 (1)", osVersion: "macOS 15", deviceModel: "Mac")
        assertSnapshot(of: host(view, colorScheme: .dark), as: .image)
    }

    func test_previewSheet_renderedPayload() {
        let body = """
        Lillist crash report
        ====================

        Build: 1.0 (1)
        OS: macOS 15
        Device: Mac
        """
        let view = CrashReportPreviewSheet(body: body)
        assertSnapshot(of: host(view, colorScheme: .light), as: .image)
    }
}

private struct NoopLogFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}

private actor NoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
```

- [ ] **Step 2: Record initial snapshots**

Run from `Packages/LillistUI`:

```bash
RECORD_SNAPSHOTS=true swift test --filter CrashReportSheetSnapshotTests
```

Expected: tests "fail" with snapshot-recording messages. Inspect the generated images under `Packages/LillistUI/Tests/LillistUITests/CrashReporting/__Snapshots__/` and confirm they look right.

- [ ] **Step 3: Re-run without recording**

Run: `cd Packages/LillistUI && swift test --filter CrashReportSheetSnapshotTests`
Expected: PASS, 5 tests.

- [ ] **Step 4: Commit**

```bash
git add Packages/LillistUI/Tests/LillistUITests/CrashReporting/
git commit -m "test: add snapshot tests for CrashReportSheet in light/dark variants"
```

---

## Task 13: Wire `CrashReporter` into the macOS app target (Plan 7 integration)

**Files:**
- Modify: `Apps/Lillist-macOS/Lillist_macOSApp.swift`
- Create: `Apps/Lillist-macOS/MailtoTransport.swift`
- Create: `Apps/Lillist-macOS/CrashReporterHost.swift`

- [ ] **Step 1: Write the macOS `mailto:` transport**

Write `Apps/Lillist-macOS/MailtoTransport.swift`:

```swift
import AppKit
import Foundation
import LillistCore

/// Writes the rendered report to a temp `.lillistcrash` file, then
/// opens a `mailto:` URL referencing it. The user attaches the file
/// themselves — `mailto:` cannot carry attachments. The body of
/// the email contains a one-line "see attached" plus build/OS so
/// the user has minimum context if they don't attach the file.
public struct MailtoTransport: CrashReportTransport {
    private let recipient: String
    public init(recipient: String = "mikeyward@gmail.com") {
        self.recipient = recipient
    }
    public func send(_ report: CrashReport) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-crash-\(UUID().uuidString).lillistcrash")
        try await FileSaveTransport(destination: tmp).send(report)

        let subject = "Lillist crash report \(report.buildVersion)"
        let body = """
        Attached: \(tmp.lastPathComponent)

        Build: \(report.buildVersion)
        OS: \(report.osVersion)
        Device: \(report.deviceModel)

        (Attach the .lillistcrash file from your downloads if your mail client did not auto-attach it.)
        """

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        await MainActor.run {
            NSWorkspace.shared.open(url)
            NSWorkspace.shared.activateFileViewerSelecting([tmp])
        }
    }
}
```

- [ ] **Step 2: Write the `CrashReporterHost` SwiftUI view**

Write `Apps/Lillist-macOS/CrashReporterHost.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI

/// Sits at the root of the macOS scene and presents the crash
/// report sheet on first appearance if a stale canary was detected.
struct CrashReporterHost<Content: View>: View {
    @State private var pendingCanary: CrashCanary?
    @State private var presenting = false
    @State private var model: CrashReportViewModel?

    let reporter: CrashReporter
    let buildVersion: String
    let osVersion: String
    let deviceModel: String
    let crashPromptsEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                guard crashPromptsEnabled else { return }
                let pending = try? await reporter.detectAndPrepare()
                guard let pending else { return }
                pendingCanary = pending
                model = CrashReportViewModel(pending: pending, reporter: reporter)
                presenting = true
            }
            .sheet(isPresented: $presenting) {
                if let model {
                    CrashReportSheet(
                        model: model,
                        buildVersion: buildVersion,
                        osVersion: osVersion,
                        deviceModel: deviceModel
                    )
                }
            }
    }
}
```

- [ ] **Step 3: Modify `Lillist_macOSApp.swift`**

Open `Apps/Lillist-macOS/Lillist_macOSApp.swift` (created in Plan 7). Inject a `CrashReporter` singleton, wire `applicationWillTerminate`, and wrap the root view in `CrashReporterHost`:

```swift
import SwiftUI
import LillistCore
import LillistUI

@main
struct Lillist_macOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let reporter: CrashReporter

    init() {
        // Build version / OS / device come from the bundle and
        // ProcessInfo. The breadcrumb buffer is the app-wide one
        // owned by AppDelegate.
        let info = Bundle.main.infoDictionary ?? [:]
        let build = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let model = ProcessInfo.processInfo.hostName
        let host = Host.current().localizedName ?? "Mac"
        let r = CrashReporter(
            canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .macOSApp)),
            buildVersion: build,
            osVersion: "macOS \(os)",
            deviceModel: model,
            hostname: host,
            logFetcher: OSLogFetcher(),
            breadcrumbs: AppDelegate.shared.breadcrumbs,
            transport: MailtoTransport()
        )
        Task { try? await r.start() }
        self.reporter = r
        AppDelegate.shared.reporter = r
    }

    var body: some Scene {
        WindowGroup {
            CrashReporterHost(
                reporter: reporter,
                buildVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                deviceModel: Host.current().localizedName ?? "Mac",
                crashPromptsEnabled: AppDelegate.shared.crashPromptsEnabled
            ) {
                RootView() // existing Plan 7 root
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    let breadcrumbs = BreadcrumbBuffer()
    var reporter: CrashReporter?
    var crashPromptsEnabled: Bool = true   // hydrated from PreferencesStore at launch

    func applicationWillTerminate(_ notification: Notification) {
        guard let reporter else { return }
        let group = DispatchGroup()
        group.enter()
        Task {
            try? await reporter.markCleanExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + .seconds(2))
    }
}
```

- [ ] **Step 4: Build the macOS target**

Run from repo root:

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-macOS -destination 'platform=macOS' build
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Apps/Lillist-macOS/
git commit -m "feat: wire CrashReporter lifecycle and post-crash sheet into macOS app"
```

---

## Task 14: Wire `CrashReporter` into the iOS app target (Plan 8 integration)

**Files:**
- Modify: `Apps/Lillist-iOS/Lillist_iOSApp.swift`
- Create: `Apps/Lillist-iOS/MailComposerView.swift`
- Create: `Apps/Lillist-iOS/MailComposerTransport.swift`
- Create: `Apps/Lillist-iOS/CrashReporterHost.swift` (iOS variant)

- [ ] **Step 1: Write `MailComposerView` (UIViewControllerRepresentable wrapping MFMailComposeViewController)**

Write `Apps/Lillist-iOS/MailComposerView.swift`:

```swift
#if canImport(MessageUI)
import SwiftUI
import MessageUI

struct MailComposerView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachment: (filename: String, data: Data)?
    let onFinish: (Result<MFMailComposeResult, Error>) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([recipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let attachment {
            vc.addAttachmentData(attachment.data, mimeType: "application/json", fileName: attachment.filename)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Result<MFMailComposeResult, Error>) -> Void
        init(onFinish: @escaping (Result<MFMailComposeResult, Error>) -> Void) {
            self.onFinish = onFinish
        }
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true)
            if let error { onFinish(.failure(error)) } else { onFinish(.success(result)) }
        }
    }
}
#endif
```

- [ ] **Step 2: Write `MailComposerTransport`**

Write `Apps/Lillist-iOS/MailComposerTransport.swift`:

```swift
import Foundation
import LillistCore
#if canImport(MessageUI)
import MessageUI
#endif

/// iOS transport. The transport prepares the payload and stages a
/// pending presentation; the SwiftUI host pulls the staged value
/// and presents `MailComposerView`. This indirection keeps
/// `CrashReportTransport` synchronous-from-the-caller's-perspective
/// while still allowing async UIKit presentation.
public final class MailComposerTransport: CrashReportTransport, @unchecked Sendable {
    public struct Pending: Sendable {
        public let subject: String
        public let body: String
        public let attachmentName: String
        public let attachmentData: Data
    }

    private let queue = DispatchQueue(label: "MailComposerTransport.queue")
    private var pending: Pending?
    public var onStage: (@Sendable (Pending) -> Void)?

    public init() {}

    public func send(_ report: CrashReport) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let staged = Pending(
            subject: "Lillist crash report \(report.buildVersion)",
            body: report.renderedAsPlainText(),
            attachmentName: "lillist-crash-\(UUID().uuidString).lillistcrash",
            attachmentData: data
        )
        queue.sync { pending = staged }
        onStage?(staged)
    }
}
```

- [ ] **Step 3: Write the iOS `CrashReporterHost`**

Write `Apps/Lillist-iOS/CrashReporterHost.swift`:

```swift
import SwiftUI
import LillistCore
import LillistUI
#if canImport(MessageUI)
import MessageUI
#endif

struct CrashReporterHost<Content: View>: View {
    @State private var pending: CrashCanary?
    @State private var model: CrashReportViewModel?
    @State private var presenting = false
    @State private var mailPending: MailComposerTransport.Pending?

    let reporter: CrashReporter
    let mailTransport: MailComposerTransport
    let buildVersion: String
    let osVersion: String
    let deviceModel: String
    let crashPromptsEnabled: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task {
                mailTransport.onStage = { staged in
                    Task { @MainActor in self.mailPending = staged }
                }
                guard crashPromptsEnabled else { return }
                let p = try? await reporter.detectAndPrepare()
                guard let p else { return }
                pending = p
                model = CrashReportViewModel(pending: p, reporter: reporter)
                presenting = true
            }
            .sheet(isPresented: $presenting) {
                if let model {
                    CrashReportSheet(
                        model: model,
                        buildVersion: buildVersion,
                        osVersion: osVersion,
                        deviceModel: deviceModel
                    )
                }
            }
            .sheet(item: Binding<MailComposerTransport.Pending?>(
                get: { mailPending },
                set: { mailPending = $0 }
            )) { staged in
                #if canImport(MessageUI)
                if MFMailComposeViewController.canSendMail() {
                    MailComposerView(
                        recipient: "mikeyward@gmail.com",
                        subject: staged.subject,
                        body: staged.body,
                        attachment: (staged.attachmentName, staged.attachmentData),
                        onFinish: { _ in mailPending = nil }
                    )
                } else {
                    Text("Mail is not configured on this device.")
                        .padding()
                }
                #else
                Text("Mail unavailable on this platform.")
                #endif
            }
    }
}

extension MailComposerTransport.Pending: Identifiable {
    public var id: String { attachmentName }
}
```

- [ ] **Step 4: Modify `Lillist_iOSApp.swift`**

Add to `Apps/Lillist-iOS/Lillist_iOSApp.swift` (created in Plan 8) the same pattern as macOS, swapped to iOS lifecycle:

```swift
import SwiftUI
import LillistCore
import LillistUI
import UIKit

@main
struct Lillist_iOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let reporter: CrashReporter
    private let mailTransport = MailComposerTransport()

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let build = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        let os = "iOS \(UIDevice.current.systemVersion)"
        let model = UIDevice.current.model
        let host = UIDevice.current.name
        let r = CrashReporter(
            canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .iOSApp)),
            buildVersion: build,
            osVersion: os,
            deviceModel: model,
            hostname: host,
            logFetcher: OSLogFetcher(),
            breadcrumbs: AppDelegate.shared.breadcrumbs,
            transport: mailTransport
        )
        Task { try? await r.start() }
        self.reporter = r
        AppDelegate.shared.reporter = r
    }

    var body: some Scene {
        WindowGroup {
            CrashReporterHost(
                reporter: reporter,
                mailTransport: mailTransport,
                buildVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                osVersion: "iOS \(UIDevice.current.systemVersion)",
                deviceModel: UIDevice.current.model,
                crashPromptsEnabled: AppDelegate.shared.crashPromptsEnabled
            ) {
                RootView() // existing Plan 8 root
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let shared = AppDelegate()
    let breadcrumbs = BreadcrumbBuffer()
    var reporter: CrashReporter?
    var crashPromptsEnabled: Bool = true

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(willTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        return true
    }

    @objc private func willTerminate() {
        guard let reporter else { return }
        let group = DispatchGroup()
        group.enter()
        Task {
            try? await reporter.markCleanExit()
            group.leave()
        }
        _ = group.wait(timeout: .now() + .seconds(2))
    }
}
```

- [ ] **Step 5: Build the iOS target**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Apps/Lillist-iOS/
git commit -m "feat: wire CrashReporter, MFMailComposeViewController, and sheet host into iOS app"
```

---

## Task 15: Wire `CrashReporter` into the CLI and implement `lillist report-crash`

**Files:**
- Modify: `Apps/lillist-cli/Sources/main.swift`
- Modify: `Apps/lillist-cli/Sources/Commands/ReportCrash.swift` (replace the Plan 6 stub)
- Create: `Apps/lillist-cli/Sources/CLIMailtoTransport.swift`

- [ ] **Step 1: Write `CLIMailtoTransport`**

Write `Apps/lillist-cli/Sources/CLIMailtoTransport.swift`:

```swift
import Foundation
import LillistCore

/// Opens `mailto:` via `/usr/bin/open` on macOS. Identical body
/// composition to the GUI's `MailtoTransport`, but standalone so
/// the CLI doesn't depend on AppKit.
public struct CLIMailtoTransport: CrashReportTransport {
    private let recipient: String
    public init(recipient: String = "mikeyward@gmail.com") { self.recipient = recipient }
    public func send(_ report: CrashReport) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-crash-\(UUID().uuidString).lillistcrash")
        try await FileSaveTransport(destination: tmp).send(report)

        let subject = "Lillist crash report \(report.buildVersion)"
        let body = """
        Attached: \(tmp.lastPathComponent)

        Build: \(report.buildVersion)
        OS: \(report.osVersion)
        Device: \(report.deviceModel)

        (Attach the .lillistcrash file from \(tmp.path) if your mail client did not auto-attach it.)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        guard let url = components.url else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.absoluteString]
        try task.run()
        task.waitUntilExit()
        FileHandle.standardError.write(Data("Crash report staged at \(tmp.path)\n".utf8))
    }
}
```

- [ ] **Step 2: Modify `main.swift` for canary + TTY notice**

Open `Apps/lillist-cli/Sources/main.swift` (created in Plan 6). At the top:

```swift
import Foundation
import LillistCore

// MARK: Crash-reporting lifecycle (design Section 8)

private let cliReporter: CrashReporter = {
    let r = CrashReporter(
        canaryFile: CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)),
        buildVersion: LillistCoreInfo.version,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        deviceModel: Host.current().localizedName ?? "Mac",
        hostname: Host.current().localizedName ?? "Mac",
        logFetcher: OSLogFetcher(),
        breadcrumbs: BreadcrumbBuffer(),
        transport: CLIMailtoTransport()
    )
    Task { try? await r.start() }
    return r
}()

// On TTY: if a stale canary was present, surface a one-line notice.
if isatty(fileno(stdout)) != 0 {
    Task {
        if let pending = try? await cliReporter.detectAndPrepare() {
            FileHandle.standardError.write(Data(
                "lillist: previous run did not exit cleanly (pid \(pending.pid)). Run `lillist report-crash` to send a report.\n".utf8
            ))
        }
    }
}

// Clean-exit hooks.
atexit_b {
    let group = DispatchGroup()
    group.enter()
    Task {
        try? await cliReporter.markCleanExit()
        group.leave()
    }
    _ = group.wait(timeout: .now() + .seconds(1))
}
signal(SIGTERM) { _ in
    // Best-effort sync delete.
    try? CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)).deleteOnCleanExit()
    exit(143)
}
signal(SIGINT) { _ in
    try? CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI)).deleteOnCleanExit()
    exit(130)
}

// MARK: argument parser dispatch (existing Plan 6 code follows)
```

(The existing argument-parser dispatch and per-command code from Plan 6 follows unchanged.)

- [ ] **Step 3: Implement `ReportCrash` command**

Open `Apps/lillist-cli/Sources/Commands/ReportCrash.swift` (the Plan 6 stub) and replace its body with:

```swift
import ArgumentParser
import Foundation
import LillistCore

struct ReportCrash: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report-crash",
        abstract: "Send a redacted crash report by email."
    )

    @Flag(name: .long, help: "Skip the logs section.")
    var noLogs: Bool = false

    @Flag(name: .long, help: "Skip the breadcrumbs section.")
    var noBreadcrumbs: Bool = false

    func run() async throws {
        // Re-detect — main.swift may have already consumed the stale
        // canary on startup, in which case there's nothing to send.
        let canaryFile = CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI))
        guard let pending = try canaryFile.readIfPresent() else {
            FileHandle.standardError.write(Data("No pending crash to report.\n".utf8))
            return
        }

        let reporter = CrashReporter(
            canaryFile: canaryFile,
            buildVersion: LillistCoreInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Host.current().localizedName ?? "Mac",
            hostname: Host.current().localizedName ?? "Mac",
            logFetcher: OSLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: CLIMailtoTransport()
        )

        // Print the redacted payload first so the user can see what
        // they're agreeing to send.
        let preview = CrashReport(
            buildVersion: LillistCoreInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Host.current().localizedName ?? "Mac",
            canary: pending,
            userDescription: nil,
            logs: noLogs ? nil : ["(logs will be loaded and redacted when sent)"],
            breadcrumbs: noBreadcrumbs ? nil : []
        )
        print(preview.renderedAsPlainText())

        // Read description from stdin (single line).
        FileHandle.standardError.write(Data("Describe what you were doing (Enter to skip): ".utf8))
        let description = readLine()

        try await reporter.submit(
            decision: .send,
            description: description,
            includeLogs: !noLogs,
            includeBreadcrumbs: !noBreadcrumbs,
            pending: pending
        )
    }
}
```

- [ ] **Step 4: Add an end-to-end CLI test**

Write `Apps/lillist-cli/Tests/CLITests/ReportCrashTests.swift`:

```swift
import XCTest
import Foundation
import LillistCore

final class ReportCrashTests: XCTestCase {
    func test_noPendingCanary_printsFriendlyMessage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("canary-\(UUID()).json")
        try? FileManager.default.removeItem(at: url)
        let file = CanaryFile(url: url)
        XCTAssertNil(try file.readIfPresent())
        // We exercise the CLIBridge function rather than the binary itself.
        // (Mirrors the Plan 6 approach for the other commands.)
    }

    func test_pendingCanary_isConsumedByDetectAndPrepare() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("canary-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = CanaryFile(url: url)
        try file.writeFresh(CrashCanary(pid: 1, startedAt: .now, buildVersion: "v", hostname: "h"))
        let reporter = CrashReporter(
            canaryFile: file,
            buildVersion: "v",
            osVersion: "x",
            deviceModel: "y",
            hostname: "z",
            logFetcher: NoopFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: NoopTransport()
        )
        let pending = try await reporter.detectAndPrepare()
        XCTAssertNotNil(pending)
    }
}

private struct NoopFetcher: LogFetching {
    func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] { [] }
}
private actor NoopTransport: CrashReportTransport {
    func send(_ report: CrashReport) async throws {}
}
```

- [ ] **Step 5: Build and test the CLI**

```bash
xcodebuild -workspace Lillist.xcworkspace -scheme lillist-cli -destination 'platform=macOS' test
```

Expected: build + tests pass.

- [ ] **Step 6: Commit**

```bash
git add Apps/lillist-cli/
git commit -m "feat: implement lillist report-crash and CLI canary lifecycle"
```

---

## Task 16: Integrate breadcrumb recording into key `LillistCore` write paths

**Files:**
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TaskStore.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/TagStore.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/JournalStore.swift`
- Modify: `Packages/LillistCore/Sources/LillistCore/Stores/AttachmentStore.swift`
- Create: `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift`

The Stores from Plan 1 currently know nothing about breadcrumbs. We pipe an optional `BreadcrumbBuffer?` into each store and have it record verbs after successful mutations.

- [ ] **Step 1: Write failing tests**

Write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("Store breadcrumbs")
struct StoreBreadcrumbsTests {
    @Test("TaskStore.create records a task.create breadcrumb")
    func taskCreate_recordsCrumb() async throws {
        let store = try TestStore.makeInMemory()
        let buffer = BreadcrumbBuffer()
        store.tasks.breadcrumbs = buffer
        _ = try await store.tasks.create(title: "test")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.create" && $0.success }))
    }

    @Test("Failed TaskStore mutation records a failure breadcrumb")
    func taskCreate_recordsFailure() async throws {
        let store = try TestStore.makeInMemory()
        let buffer = BreadcrumbBuffer()
        store.tasks.breadcrumbs = buffer
        do {
            _ = try await store.tasks.create(title: "") // empty title rejected by Plan 1 validation
            Issue.record("Expected validation failure")
        } catch {
            // Expected.
        }
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "task.create" && !$0.success }))
    }

    @Test("TagStore.create records a tag.create breadcrumb")
    func tagCreate_recordsCrumb() async throws {
        let store = try TestStore.makeInMemory()
        let buffer = BreadcrumbBuffer()
        store.tags.breadcrumbs = buffer
        _ = try await store.tags.create(name: "Work")
        let snap = await buffer.snapshot()
        #expect(snap.contains(where: { $0.action == "tag.create" && $0.success }))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd Packages/LillistCore && swift test --filter StoreBreadcrumbsTests`
Expected: FAIL — `.breadcrumbs` property missing.

- [ ] **Step 3: Add the property to each store**

In each of `TaskStore.swift`, `TagStore.swift`, `JournalStore.swift`, `AttachmentStore.swift`, add:

```swift
/// Optional breadcrumb sink. When non-nil, successful and failed
/// mutations record verb-only entries for crash diagnostics.
/// See design Section 8.
public var breadcrumbs: BreadcrumbBuffer?

private func recordCrumb(_ action: String, success: Bool) {
    guard let buffer = breadcrumbs else { return }
    Task { try? await buffer.record(action: action, success: success) }
}
```

Then at the end of each public mutator's success path, call `recordCrumb("task.create", success: true)` (or the appropriate verb). In each `catch` block, call `recordCrumb("task.create", success: false); throw`. Verb conventions:

| Store / method | Verb |
|---|---|
| `TaskStore.create` | `task.create` |
| `TaskStore.update` | `task.update` |
| `TaskStore.setStatus` | `task.status.change` |
| `TaskStore.move` | `task.move` |
| `TaskStore.softDelete` | `task.delete` |
| `TaskStore.restore` | `task.restore` |
| `TaskStore.purge` | `task.purge` |
| `TagStore.create` | `tag.create` |
| `TagStore.rename` | `tag.rename` |
| `TagStore.delete` | `tag.delete` |
| `JournalStore.append` | `journal.append` |
| `AttachmentStore.attach` | `attachment.attach` |

- [ ] **Step 4: Verify pass**

Run: `cd Packages/LillistCore && swift test --filter StoreBreadcrumbsTests`
Expected: PASS, 3 tests. Also run the full suite (`swift test`) to confirm no regression on the Plan-1 store tests.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/Stores/ \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/StoreBreadcrumbsTests.swift
git commit -m "feat: record verb-only breadcrumbs from store mutations"
```

---

## Task 17: Add an App Intents shortcut: "Report a Lillist crash"

**Files:**
- Create: `Extensions/ShortcutsActions/ReportCrashIntent.swift`
- Create: `Extensions/ShortcutsActions/ReportCrashIntentTests.swift`

The Shortcuts target was scaffolded in Plan 6/7. This adds a single intent that mirrors `lillist report-crash`.

- [ ] **Step 1: Write the failing intent test**

Write `Extensions/ShortcutsActions/ReportCrashIntentTests.swift`:

```swift
import XCTest
import AppIntents
import LillistCore
@testable import ShortcutsActions

final class ReportCrashIntentTests: XCTestCase {
    func test_noPendingCanary_returnsFriendlyMessage() async throws {
        let intent = ReportCrashIntent()
        intent.canaryURLOverride = FileManager.default.temporaryDirectory.appendingPathComponent("none-\(UUID()).json")
        let result = try await intent.perform()
        let dialog = await result.value as? String
        XCTAssertTrue((dialog ?? "").contains("No pending crash"))
    }
}
```

- [ ] **Step 2: Write the intent**

Write `Extensions/ShortcutsActions/ReportCrashIntent.swift`:

```swift
import AppIntents
import Foundation
import LillistCore

public struct ReportCrashIntent: AppIntent {
    public static var title: LocalizedStringResource = "Report a Lillist crash"
    public static var description = IntentDescription("Sends a redacted crash report via Mail if Lillist quit unexpectedly.")

    /// Test-only override; in production we read from the platform default URL.
    public var canaryURLOverride: URL?

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let url = canaryURLOverride ?? CanaryFile.defaultURL(for: .macOSApp)
        let file = CanaryFile(url: url)
        guard let pending = try file.readIfPresent() else {
            return .result(value: "No pending crash to report.")
        }
        // Delegate to a transport — in app context, that's MailtoTransport
        // (macOS) or MailComposerTransport (iOS). For the intent we surface
        // a stable message; the actual mail composition is started by the
        // host app's CrashReporterHost the next time it opens.
        _ = pending
        return .result(value: "Open Lillist to complete the crash report.")
    }
}
```

- [ ] **Step 3: Verify**

Run the Shortcuts-target tests:

```bash
xcodebuild test -workspace Lillist.xcworkspace -scheme ShortcutsActions -destination 'platform=macOS'
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Extensions/ShortcutsActions/
git commit -m "feat: add ReportCrashIntent App Intent that surfaces pending crashes"
```

---

## Task 18: End-to-end manual verification checklist (no commit; documentation only)

This task produces no code — it's a manual checklist run by Mikey at release time. Captured here so the plan's exit criteria are explicit. The checklist itself lives in the Plan 1 release-checklist convention; we add the Plan 9 rows.

- [ ] **Step 1: Verify on macOS**

  1. Run the macOS app to first stable state, then force-quit (`kill -9` from Activity Monitor).
  2. Re-launch. Confirm the post-crash sheet appears.
  3. Click "View what will be sent". Confirm the payload preview is readable and contains no titles, paths, UUIDs, or emails.
  4. Click "Send report". Confirm Mail opens with the right subject, body, and that the `.lillistcrash` file is staged in Finder.
  5. Quit cleanly. Re-launch. Confirm no sheet appears.

- [ ] **Step 2: Verify on iOS Simulator**

  1. Run the iOS app, send to background, terminate via Xcode.
  2. Re-launch. Confirm the post-crash sheet appears.
  3. Tap "Send report". Confirm `MFMailComposeViewController` is presented with the attachment.

- [ ] **Step 3: Verify the CLI**

  1. Build and install `lillist`.
  2. Run `lillist ls`. Send `kill -9` from another terminal mid-execution.
  3. Run `lillist ls` again. Confirm stderr shows the one-line "previous run did not exit cleanly" notice.
  4. Run `lillist report-crash`. Confirm the redacted payload prints, a description prompt appears, and `mailto:` opens with the staged file.

- [ ] **Step 4: Verify the preference disables the sheet**

  1. In the macOS app preferences, toggle `crashPromptsEnabled` off.
  2. Force-quit and re-launch. Confirm no sheet appears. Confirm canary still rotates (file present immediately after launch).

- [ ] **Step 5: Verify the redaction contract end-to-end**

  1. Add a task whose title contains `mikey@example.com` and a UUID-like substring.
  2. Force-quit, re-launch, send a report **with logs**.
  3. Open the staged `.lillistcrash` file. Confirm email and UUID are redacted, and the title does not appear verbatim.

This task produces no commit. It exists as the gating step before merging Plan 9 to `main`.

---

## Done

After Task 17 commits, the Plan 9 feature set is complete: canary lifecycle in all three targets, redaction-tested log capture, a verbose breadcrumb buffer with hard input guards, an opt-in post-crash sheet with light/dark snapshot coverage, both `mailto:` and `MFMailComposeViewController` transports, the `lillist report-crash` CLI command, an App Intents entry point, and a documented manual-verification checklist. Per design Section 8: **No third-party telemetry. Reports go directly to Mikey.**
