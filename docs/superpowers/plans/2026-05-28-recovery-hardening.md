# Recovery Hardening Implementation Plan

> **📍 STATUS — ⬜ PENDING — Wave 7.**
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–6 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-6.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-7.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the destructive sync-mode swap a real recovery runbook — a pre-flight free-space check before the quarantine copy, a tested restore-from-backup path, and failure-injection tests for the disk-full and successful-restore cases — so a mid-migration failure or crash never strands the user's only data.

**Architecture:** Add a pure, filesystem-only `DiskSpaceProbe` seam (free-space + estimated-needed bytes) and a `LillistError.insufficientDiskSpace` case; have `QuarantineManager.copyStore(at:)` precondition free space against the live store's footprint and throw clearly when short. The pre-flight goes in `copyStore(at:)` — not `quarantineStore(at:)` — because `runMigration` takes its recovery anchor by COPYING (not moving) the now-closed store; a check added only to `quarantineStore` would never fire during a migration. Wire that pre-flight into `MigrationCoordinator.runMigration` so it throws before the irreversible zone-erase, emitting a `.failed` journal/phase so the existing `SyncMigrationRecoverySheet` surfaces it; then add a disk-full pre-flight test (the `restoreFromBackup` `test-2` gap is already closed — see Task 6/7's note), all in Swift Testing matching the neighboring `MigrationCoordinatorTests`/`QuarantineManagerTests` suites.

**Tech Stack:** Swift 6.2, Foundation (`FileManager`, `URLResourceValues.volumeAvailableCapacityForImportantUsageKey`, `.totalFileAllocatedSize`), Core Data (`PersistenceHost`/`PersistenceController` only via existing test factories), Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`).

**Source findings:** Closes Critic blind spot #5 (*thin data-loss/recovery story*) and its sub-claims `test-2` (`restoreFromBackup` untested) and the pre-destructive-op disk-space-check gap. Partially reinforces `persist-3`/`sync-4` (recovery anchor integrity) without duplicating the store-swap-safety plan's transactional-swap work.

---

## File Structure

| Path | Create/Modify | Single responsibility |
|------|---------------|------------------------|
| `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift` | Modify | Add `insufficientDiskSpace(neededBytes:availableBytes:)` case + its `errorDescription`. |
| `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift` | Create | Pure, injectable free-space + footprint probe (`DiskSpaceProbing` protocol, `FileManagerDiskSpaceProbe` default, fake-friendly seam). |
| `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift` | Modify | Pre-flight free-space check (via injected probe) at the top of `copyStore(at:)` — the method `runMigration` actually calls; expose `requiredBytesForQuarantine(of:)` helper. |
| `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` | Modify | Call the disk-space pre-flight before the irreversible quarantine/erase in `runMigration`; surface `.failed` cleanly on shortfall. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/DiskSpaceProbeTests.swift` | Create | Unit tests for `FileManagerDiskSpaceProbe` footprint math + fake-probe contract. |
| `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift` | Modify | Disk-full quarantine test asserting `insufficientDiskSpace`; success-path-with-probe test. |
| `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift` | Modify | One disk-full pre-flight `runMigration` test leaving the journal `.failed` and skipping the zone erase. (`restoreFromBackup` is already covered by `MigrationRecoveryTests.swift` — test-2 is closed.) |

---

## Task 1: Add `insufficientDiskSpace` to `LillistError`

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift` (case list ~lines 14–25; `errorDescription` switch ~lines 31–55).

- [ ] **Step 1: Write the failing test** — add this `@Test` to the existing `LillistError` test suite if one exists, else create `Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorDiskSpaceTests.swift` with the complete file:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("LillistError.insufficientDiskSpace")
struct LillistErrorDiskSpaceTests {
    @Test("insufficientDiskSpace is Equatable on both byte fields")
    func equatable() {
        let a = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 50)
        let b = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 50)
        let c = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 49)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("errorDescription names both the needed and available byte counts")
    func description() {
        let err = LillistError.insufficientDiskSpace(neededBytes: 4096, availableBytes: 1024)
        let text = err.errorDescription ?? ""
        #expect(text.contains("4096"))
        #expect(text.contains("1024"))
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LillistErrorDiskSpaceTests`. Expected: compile error `type 'LillistError' has no member 'insufficientDiskSpace'`.

- [ ] **Step 3: Implement the minimal change** — add the case to the enum (after `case attachmentFetchFailed(url: URL)`):

```swift
    case attachmentFetchFailed(url: URL)
    /// Plan 21 recovery: a destructive store operation needs more free
    /// disk space than the volume can provide. Carries both figures so
    /// the recovery UI can tell the user exactly how short they are.
    case insufficientDiskSpace(neededBytes: Int64, availableBytes: Int64)
    case migrationRequired
```

  and add the matching arm to the `errorDescription` switch (after the `attachmentFetchFailed` arm):

```swift
        case .attachmentFetchFailed(let url):
            return "Could not fetch attachment from \(url.absoluteString)."
        case .insufficientDiskSpace(let neededBytes, let availableBytes):
            return "Not enough free disk space to safely back up the data store: \(neededBytes) bytes needed, \(availableBytes) bytes available."
        case .migrationRequired:
            return "A data migration is required to open this store."
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter LillistErrorDiskSpaceTests`. Expected: `Test Suite 'LillistError.insufficientDiskSpace' passed` with 2 tests passing.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Validation/LillistErrorDiskSpaceTests.swift
git commit -m "feat(core): add LillistError.insufficientDiskSpace for recovery pre-flight"
```

---

## Task 2: Create the `DiskSpaceProbe` seam

**Files:**
- Create `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift`.
- Create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/DiskSpaceProbeTests.swift`.

Rationale: free-space and footprint math must be injectable so the disk-full path is testable without actually filling a real volume. `FileManager`-backed default is production; a fake satisfies the same protocol in tests.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/Persistence/DiskSpaceProbeTests.swift` with the complete file:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("DiskSpaceProbe")
struct DiskSpaceProbeTests {
    private func makeTempRoot() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Lillist-diskprobe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Footprint sums the SQLite triplet that exists on disk")
    func footprintSumsTriplet() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0xAB, count: 4096).write(to: storeURL)
        try Data(repeating: 0xCD, count: 2048).write(to: storeURL.appendingPathExtension("wal"))
        try Data(repeating: 0xEF, count: 1024).write(to: storeURL.appendingPathExtension("shm"))
        let probe = FileManagerDiskSpaceProbe()
        let footprint = try probe.footprint(of: storeURL)
        // Allocated size rounds up to block boundaries, so assert a
        // lower bound on the logical total rather than an exact figure.
        #expect(footprint >= 4096 + 2048 + 1024)
    }

    @Test("Footprint of a missing store is zero")
    func footprintMissingIsZero() throws {
        let root = try makeTempRoot()
        let probe = FileManagerDiskSpaceProbe()
        #expect(try probe.footprint(of: root.appendingPathComponent("nope.sqlite")) == 0)
    }

    @Test("Available capacity for the temp dir is positive on a real volume")
    func availableIsPositive() throws {
        let root = try makeTempRoot()
        let probe = FileManagerDiskSpaceProbe()
        #expect(try probe.availableCapacity(forVolumeContaining: root) > 0)
    }

    @Test("Fake probe returns its stubbed figures")
    func fakeContract() throws {
        let fake = FakeDiskSpaceProbe(availableBytes: 10, footprintBytes: 7)
        #expect(try fake.availableCapacity(forVolumeContaining: URL(fileURLWithPath: "/")) == 10)
        #expect(try fake.footprint(of: URL(fileURLWithPath: "/anything")) == 7)
    }
}

/// Test double living in the test target so production stays lean.
struct FakeDiskSpaceProbe: DiskSpaceProbing {
    var availableBytes: Int64
    var footprintBytes: Int64
    func availableCapacity(forVolumeContaining url: URL) throws -> Int64 { availableBytes }
    func footprint(of storeURL: URL) throws -> Int64 { footprintBytes }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter DiskSpaceProbeTests`. Expected: compile error `cannot find type 'DiskSpaceProbing' in scope` / `cannot find 'FileManagerDiskSpaceProbe' in scope`.

- [ ] **Step 3: Implement the minimal change** — create `Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift` with the complete file:

```swift
import Foundation

/// Pure, injectable probe for the two filesystem facts the recovery
/// pre-flight needs: how much room a volume has, and how big the live
/// store currently is. A protocol so the disk-full path is testable
/// without actually exhausting a real volume.
///
/// Operates purely on the filesystem; never opens Core Data.
public protocol DiskSpaceProbing: Sendable {
    /// Free bytes the OS reports as available for "important" usage on
    /// the volume that contains `url`. Uses
    /// `volumeAvailableCapacityForImportantUsageKey`, which reflects
    /// space the system would free up (purgeables) for a real write —
    /// the honest figure for a backup copy.
    func availableCapacity(forVolumeContaining url: URL) throws -> Int64

    /// Total on-disk footprint of the SQLite store at `storeURL` plus
    /// its `-wal` / `-shm` sidecars. Returns `0` if the main file is
    /// absent (nothing to back up).
    func footprint(of storeURL: URL) throws -> Int64
}

/// Production implementation backed by `FileManager` / `URLResourceValues`.
public struct FileManagerDiskSpaceProbe: DiskSpaceProbing {
    public init() {}

    public func availableCapacity(forVolumeContaining url: URL) throws -> Int64 {
        // Resolve against the parent directory: `url` may not exist yet
        // (e.g. a target restore location), but its containing volume
        // always does.
        let probeURL = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let values = try probeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
            throw LillistError.storeUnavailable(reason: "Could not read free space for \(probeURL.path)")
        }
        return capacity
    }

    public func footprint(of storeURL: URL) throws -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return 0 }
        var total: Int64 = 0
        for url in [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")] {
            guard fm.fileExists(atPath: url.path) else { continue }
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            // Prefer allocated size (true on-disk cost); fall back to
            // logical size if the volume doesn't report allocation.
            if let allocated = values.totalFileAllocatedSize {
                total += Int64(allocated)
            } else if let logical = values.fileSize {
                total += Int64(logical)
            }
        }
        return total
    }
}
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter DiskSpaceProbeTests`. Expected: `Test Suite 'DiskSpaceProbe' passed` with 4 tests passing.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Persistence/DiskSpaceProbe.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/DiskSpaceProbeTests.swift
git commit -m "feat(core): add injectable DiskSpaceProbe for recovery pre-flight"
```

---

## Task 3: Pre-flight free-space check in `QuarantineManager`

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift` (struct stored-property + `init` block, anchored on the `public let rootDirectory: URL` / `public init(rootDirectory:` declarations, ~approx lines 28–35; `copyStore(at:)`, anchored on its `@discardableResult public func copyStore(at storeURL: URL)` signature + opening `guard fm.fileExists` block, ~approx lines 69–73).
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift` (append new tests).

Design: the pre-flight goes in `copyStore(at:)` — the method `runMigration` calls to take its recovery anchor. `runMigration` COPIES (not moves) the now-closed store, so a disk check added only to `quarantineStore(at:)` would never fire during a migration. Inject a `DiskSpaceProbing` (default `FileManagerDiskSpaceProbe()`), and require **2× footprint** of headroom before copying — the copy path needs the source plus a copy to coexist momentarily, and the SQLite checkpoint can briefly inflate the WAL. The 2× rule is conservative and explicit. The check throws `insufficientDiskSpace` before touching any file.

- [ ] **Step 1: Write the failing test** — append these `@Test`s to `Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift` inside the existing `QuarantineManagerTests` struct (before its closing brace). They use the `FakeDiskSpaceProbe` defined in Task 2's test file (same test target, so it is in scope):

```swift
    @Test("copyStore throws insufficientDiskSpace when the probe reports too little headroom")
    func copyStoreRejectsLowDiskSpace() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        // Footprint stubbed at 4096; require 2x headroom = 8192; only
        // 8191 available -> short by one byte.
        let probe = FakeDiskSpaceProbe(availableBytes: 8191, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        #expect(throws: LillistError.insufficientDiskSpace(neededBytes: 8192, availableBytes: 8191)) {
            _ = try mgr.copyStore(at: storeURL)
        }
        // The live store must remain in place — the check is pre-flight
        // and copyStore never moves the original.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
    }

    @Test("copyStore proceeds when the probe reports ample headroom")
    func copyStoreAcceptsAmpleDiskSpace() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        let probe = FakeDiskSpaceProbe(availableBytes: 1_000_000, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date(timeIntervalSince1970: 1_700_000_000) })
        let backup = try mgr.copyStore(at: storeURL)
        // Copy, not move: the original stays put and the backup exists.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
        #expect(FileManager.default.fileExists(atPath: backup.storeURL.path) == true)
    }

    @Test("requiredBytesForQuarantine is twice the live footprint")
    func requiredBytesIsDoubleFootprint() throws {
        let root = try makeTempRoot()
        let storeURL = root.appendingPathComponent("Lillist.sqlite")
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let mgr = QuarantineManager(rootDirectory: root, diskSpaceProbe: probe, clock: { Date() })
        #expect(try mgr.requiredBytesForQuarantine(of: storeURL) == 8192)
    }
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter QuarantineManagerTests`. Expected: compile error `extra argument 'diskSpaceProbe' in call` and `value of type 'QuarantineManager' has no member 'requiredBytesForQuarantine'`.

- [ ] **Step 3: Implement the minimal change** — edit `QuarantineManager.swift`. Replace the stored-property + init block (anchor on the `public let rootDirectory: URL` declaration, ~approx lines 28–35):

```swift
    public let rootDirectory: URL
    private let clock: @Sendable () -> Date
    private var fm: FileManager { FileManager.default }

    public init(rootDirectory: URL, clock: @escaping @Sendable () -> Date = Date.init) {
        self.rootDirectory = rootDirectory
        self.clock = clock
    }
```

  with:

```swift
    public let rootDirectory: URL
    private let clock: @Sendable () -> Date
    private let diskSpaceProbe: any DiskSpaceProbing
    private var fm: FileManager { FileManager.default }

    /// Headroom multiplier applied to the live store's footprint when
    /// deciding whether a quarantine copy can proceed. 2× covers the
    /// momentary coexistence of source + copy plus WAL-checkpoint
    /// inflation during the swap.
    public static let quarantineHeadroomFactor: Int64 = 2

    public init(
        rootDirectory: URL,
        diskSpaceProbe: any DiskSpaceProbing = FileManagerDiskSpaceProbe(),
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.rootDirectory = rootDirectory
        self.diskSpaceProbe = diskSpaceProbe
        self.clock = clock
    }

    /// Bytes that must be free before `copyStore(at:)` will proceed:
    /// `quarantineHeadroomFactor ×` the live store footprint.
    public func requiredBytesForQuarantine(of storeURL: URL) throws -> Int64 {
        let footprint = try diskSpaceProbe.footprint(of: storeURL)
        return footprint * Self.quarantineHeadroomFactor
    }
```

  Then add the pre-flight check at the top of `copyStore(at:)` — the method `runMigration` actually calls to take its recovery anchor. Replace its current opening (anchor on the `@discardableResult public func copyStore(at storeURL: URL)` signature + opening `guard`, ~approx lines 69–74):

```swift
    @discardableResult
    public func copyStore(at storeURL: URL) throws -> QuarantinedBackup {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        let folderName = String(Int(clock().timeIntervalSince1970))
```

  with:

```swift
    @discardableResult
    public func copyStore(at storeURL: URL) throws -> QuarantinedBackup {
        guard fm.fileExists(atPath: storeURL.path) else {
            throw LillistError.storeUnavailable(reason: "Cannot quarantine: store missing at \(storeURL.path)")
        }
        // Pre-flight: refuse to take the recovery copy when the volume
        // can't hold source + copy at once. Throwing here leaves the
        // live store untouched (blind-spot #5: pre-destructive disk
        // check). This is the copy `runMigration` relies on, so the
        // check fires on the real migration path.
        let needed = try requiredBytesForQuarantine(of: storeURL)
        let available = try diskSpaceProbe.availableCapacity(forVolumeContaining: storeURL)
        guard available >= needed else {
            throw LillistError.insufficientDiskSpace(neededBytes: needed, availableBytes: available)
        }
        let folderName = String(Int(clock().timeIntervalSince1970))
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter QuarantineManagerTests`. Expected: `Test Suite 'QuarantineManager' passed`; the three new tests plus the existing suite all pass. The existing `quarantineStore` move tests are unaffected (the pre-flight lives only in `copyStore`); the existing `copyStore` tests still construct `QuarantineManager` with the default `FileManagerDiskSpaceProbe`, which on a real volume reports ample space, so they remain green.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Persistence/QuarantineManager.swift \
        Packages/LillistCore/Tests/LillistCoreTests/Persistence/QuarantineManagerTests.swift
git commit -m "feat(core): pre-flight disk-space check before quarantine move"
```

---

## Task 4: Wire the pre-flight into `MigrationCoordinator.runMigration`

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift` (`runMigration`'s copy-store block — step 5, anchored on the `emit(.backingUp)` line through the `quarantine.copyStore(at: storeURL)` call that sets `entry.quarantineFolderName`, ~approx lines 212–223).

> **By Wave 7, `MigrationCoordinator` also carries migration-adjacent-correctness's guards + observability brackets** — re-Read `runMigration` using those waves' handoffs before editing, and anchor by the step comments (`// 5. quarantine the now-closed old store…`) rather than line numbers.

The pre-flight already lives inside `copyStore(at:)`, so it fires automatically once `runMigration` calls it. What this task adds is **ordering correctness**: the disk check must throw *before* the CloudKit zone erase (step 6 in `runMigration`). It already does, because the merged flow is precondition (step 3) → `reconfigure` (step 4) → `copyStore` (step 5) → erase (step 6) → settle (step 7) → finalize (step 8): the copy precedes the erase. The change here is purely to make the failure legible and pin the invariant with a comment; the regression test lands in Task 5. Because `copyStore` already throws into the surrounding `do/catch` (which writes `.failed`, emits `.failed(reason:)`, records the failure breadcrumb, and rethrows), **no behavioral production change is required** — only the documenting comment so a future refactor doesn't reorder erase ahead of the copy.

- [ ] **Step 1: Write the failing test** — covered by Task 5's `runMigrationRejectsLowDiskSpace` test (the production code change is comment-only and not independently red/green-able). Skip to Step 3.

- [ ] **Step 2: Run the test, expect failure** — n/a (no new test in this task; the guarantee is asserted in Task 5).

- [ ] **Step 3: Implement the minimal change** — edit `MigrationCoordinator.swift`. The copy-store block already records the exact folder via `entry.quarantineFolderName` and copies (not moves). Add the ordering-invariant comment to step 5's leading comment. Replace the copy block (anchor on the `// 5. quarantine the now-closed old store…` comment through the `try journal.write(entry)` inside the `if` — ~approx lines 212–223):

```swift
            // 5. quarantine the now-closed old store as a recovery
            //    anchor — COPY, not move, and only if the file is still
            //    present. Record the exact folder name in the journal.
            emit(.backingUp)
            entry.state = .quarantining
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let backup = try quarantine.copyStore(at: storeURL)
                entry.quarantineFolderName = backup.folderName
                try journal.write(entry)
            }
```

  with:

```swift
            // 5. quarantine the now-closed old store as a recovery
            //    anchor — COPY, not move, and only if the file is still
            //    present. Record the exact folder name in the journal.
            //
            //    `copyStore(at:)` runs a pre-flight disk-space check and
            //    throws `LillistError.insufficientDiskSpace` *before*
            //    touching any file. That keeps the shortfall ahead of
            //    the irreversible CloudKit erase in step 6 (blind-spot
            //    #5 recovery runbook). Do NOT reorder the erase ahead of
            //    this block.
            emit(.backingUp)
            entry.state = .quarantining
            entry.lastHeartbeatAt = Date()
            try journal.write(entry)
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let backup = try quarantine.copyStore(at: storeURL)
                entry.quarantineFolderName = backup.folderName
                try journal.write(entry)
            }
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistCore`. Expected: `Build complete!` with zero warnings (warnings-as-errors). The behavioral assertion follows in Task 5.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Sources/LillistCore/Sync/MigrationCoordinator.swift
git commit -m "docs(core): pin copyStore disk-space pre-flight ahead of CloudKit erase in runMigration"
```

---

## Task 5: Test the migration disk-full pre-flight (coordinator level)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift` (helper ~approx lines 19–44; append a new `@Test`).

This test injects a `FakeDiskSpaceProbe` (from Task 2's test file) reporting zero free space into the coordinator's `QuarantineManager`, runs `beginEnable(.replaceICloud)`, and asserts the call throws, the journal is left `.failed`, and `FakeCloudKitZoneEraser.callCount == 0` (the erase never ran because `copyStore` threw first).

**Critical ordering detail — read before writing the assertions.** In the merged `runMigration`, `host.reconfigure(to: targetMode)` and `syncModeStore.setMode(targetMode)` (step 4) run **before** `copyStore` (step 5). So when `copyStore` throws `insufficientDiskSpace`, the mode is **already flipped to the target** — `.iCloudSync` for `beginEnable(.replaceICloud)`. The assertions must therefore expect *post-reconfigure* state: the host's `currentMode` and the mode store both read `.iCloudSync`, and the live store was never copied (it stays put, because `copyStore` threw before touching disk). Do **not** assert the mode stayed `.localOnly`; that was the pre-Wave-1 ordering and is now false.

Inject `FakePersistenceReconfigurer(initialMode: .localOnly)` as the `host` (not a real `PersistenceHost`). The fake's `reconfigure(to:)` flips its `currentMode` without a live container, so the test needs no real bundle id and stays **ungated** (no `liveSwapAllowed`).

- [ ] **Step 1: Write the failing test** — append this `@Test` to `MigrationCoordinatorTests` (inside the struct, before its closing brace):

```swift
    @Test("runMigration aborts on insufficient disk space before erasing iCloud")
    @MainActor
    func runMigrationRejectsLowDiskSpace() async throws {
        let dir = Self.tempDir()
        let storeURL = dir.appendingPathComponent("Lillist.sqlite")
        // A non-empty live store so the copy-store block runs its
        // pre-flight (it skips entirely when the file is absent).
        try Data(repeating: 0x01, count: 4096).write(to: storeURL)

        // FakePersistenceReconfigurer keeps the test ungated: it flips
        // its currentMode without a live container, so no liveSwapAllowed.
        let host = FakePersistenceReconfigurer(initialMode: .localOnly)
        let journal = InMemoryMigrationJournalStore()
        // Zero free space, non-zero footprint -> pre-flight must throw.
        let probe = FakeDiskSpaceProbe(availableBytes: 0, footprintBytes: 4096)
        let quarantine = QuarantineManager(rootDirectory: dir, diskSpaceProbe: probe)
        let fakeEraser = FakeCloudKitZoneEraser()
        let quiesce = SyncQuiesceMonitor(bridge: CloudKitEventBridge())
        let suite = "MigrationCoordinatorTests-\(UUID().uuidString)"
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        let modeStore = SyncModeStore(suiteName: suite)
        await modeStore.setMode(.localOnly)
        let coordinator = MigrationCoordinator(
            host: host,
            journal: journal,
            quarantine: quarantine,
            zoneEraser: fakeEraser,
            quiesceMonitor: quiesce,
            notificationScheduler: nil,
            syncModeStore: modeStore,
            // A non-empty local store so the replaceICloudWithLocal
            // precondition passes and we reach reconfigure + copyStore.
            localStoreRowCount: { 1 }
        )

        await #expect(throws: LillistError.self) {
            try await coordinator.beginEnable(direction: .replaceICloud, storeURL: storeURL)
        }
        // Erase must NOT have run — copyStore threw first (step 5 < step 6).
        #expect(await fakeEraser.callCount == 0)
        // Journal left .failed so the recovery sheet can surface it.
        let finalJournal = try journal.read()
        #expect(finalJournal.state == .failed)
        #expect(finalJournal.failureReason?.contains("insufficientDiskSpace") == true)
        // POST-RECONFIGURE state: reconfigure (step 4) ran before
        // copyStore (step 5) threw, so the mode is ALREADY flipped to
        // the target on both the host and the mode store.
        #expect(await host.currentMode == .iCloudSync)
        #expect(await modeStore.currentMode() == .iCloudSync)
        // The live store was never copied out — copyStore threw before
        // touching disk, leaving the original in place.
        #expect(FileManager.default.fileExists(atPath: storeURL.path) == true)
    }
```

- [ ] **Step 2: Run the test, expect failure** — *before* Task 3/4 land this would fail to compile; after them it should compile and pass on first run (the production behavior is already correct — this test pins it). To confirm the test is meaningful, temporarily set `availableBytes: 1_000_000` in the probe and re-run: `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter runMigrationRejectsLowDiskSpace` — expect it to FAIL on `fakeEraser.callCount == 0` / `state == .failed` (with ample space, `copyStore` succeeds and the erase proceeds), proving the assertions bite. Then restore `availableBytes: 0`.

- [ ] **Step 3: Implement the minimal change** — no production change (Tasks 3–4 already deliver the behavior). Restore `availableBytes: 0` if you changed it in Step 2.

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore --filter runMigrationRejectsLowDiskSpace`. Expected: `Test Suite ... passed`, 1 test passing.

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationCoordinatorTests.swift
git commit -m "test(sync): assert runMigration aborts on low disk before iCloud erase"
```

---

## Tasks 6 & 7 — REMOVED: `test-2` is already closed

`restoreFromBackup` is fully covered by
`Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRecoveryTests.swift`,
which runs ungated under `swift test`. It already exercises every path
the original Tasks 6–7 proposed and more:

- happy path — restores contents, reverts mode, clears journal (`:39`);
- no-backup `storeUnavailable`, journal left intact (`:65`);
- recorded-folder restore that honors the journal's `quarantineFolderName`
  over the latest backup (`:78`);
- legacy-journal fallback to the latest backup when no folder is recorded
  (`:142`);
- secondary journal-write failure in the `catch` does not mask the
  original error (`:169`).

**Do NOT re-add `restoreFromBackup` tests or a `PhaseCollector`.** A
`PhaseCollector` actor already exists at
`Packages/LillistCore/Tests/LillistCoreTests/Sync/MigrationRunnerExecutingTests.swift`
(file scope) and is reused across the Sync test target. `test-2` is
closed; this plan adds no further `restoreFromBackup` coverage.

---

## Task 8: Surface the disk-full failure in the recovery UI strings

**Files:**
- Modify `Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift` (`detail` computed property ~lines 60–63).

When a migration aborts on `insufficientDiskSpace`, `runMigration` lands the journal `.failed` and the existing launch flow shows `SyncMigrationRecoverySheet`. Today the sheet's body text only narrates the *operation*, not *why* it failed. Add a short, specific line when the failure reason names a disk-space shortfall, so the user knows freeing space is the fix (not "Try Again" into the same wall). This reuses the existing `journal.failureReason` already plumbed through; no new plumbing.

The string must be added to all three `Localizable.xcstrings` per the CLAUDE.md verbatim-cross-platform rule — but it is rendered only by the shared LillistUI sheet, so only the LillistUI catalog needs the key. (iOS/macOS apps render this sheet via LillistUI; they don't re-declare the string.) Confirm with the grep in Step 4.

- [ ] **Step 1: Write the failing test** — add a snapshot/unit assertion in the LillistUI test target. First check the neighbor: `cd /Volumes/Code/mikeyward/Lillist && ls Packages/LillistUI/Tests/LillistUITests/ | grep -i sync`. If a `SyncMigrationRecoverySheet` test exists, append to it; otherwise create `Packages/LillistUI/Tests/LillistUITests/SyncMigrationRecoverySheetTests.swift`. Match the framework of the neighboring file you find (Swift Testing if it uses `import Testing`, else XCTest). Using Swift Testing, the complete file is:

```swift
import Testing
import Foundation
@testable import LillistUI
import LillistCore

@Suite("SyncMigrationRecoverySheet detail copy")
struct SyncMigrationRecoverySheetTests {
    @Test("Detail mentions freeing space when the failure was a disk shortfall")
    func diskShortfallDetail() {
        let journal = MigrationJournal(
            state: .failed,
            operation: .replaceICloudWithLocal,
            failureReason: "insufficientDiskSpace(neededBytes: 8192, availableBytes: 100)",
            previousMode: .localOnly
        )
        let detail = SyncMigrationRecoverySheet.detailText(for: journal)
        #expect(detail.localizedCaseInsensitiveContains("space"))
    }

    @Test("Detail falls back to the operation narrative for non-disk failures")
    func genericDetail() {
        let journal = MigrationJournal(
            state: .failed,
            operation: .replaceICloudWithLocal,
            failureReason: "syncFailure(underlying: \"network\")",
            previousMode: .localOnly
        )
        let detail = SyncMigrationRecoverySheet.detailText(for: journal)
        #expect(detail.localizedCaseInsensitiveContains("replacing iCloud"))
    }
}
```

- [ ] **Step 2: Run the test, expect failure** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter SyncMigrationRecoverySheetTests`. Expected: compile error `type 'SyncMigrationRecoverySheet' has no member 'detailText'`.

- [ ] **Step 3: Implement the minimal change** — edit `SyncMigrationRecoverySheet.swift`. Replace the `detail` computed property (current lines 60–63):

```swift
    private var detail: String {
        let operation = journal.operation.map(operationDescription) ?? "the previous sync change"
        return String(localized: "Lillist couldn't finish \(operation). Restore from the backup we made before the change, or try again.", bundle: .module)
    }
```

  with a body that delegates to a `nonisolated static` helper (per the CLAUDE.md rule: pure value-math hung off a View should be `nonisolated static` so non-MainActor test callers can use it):

```swift
    private var detail: String { Self.detailText(for: journal) }

    /// Pure, testable narrative for the recovery sheet body. Adds a
    /// disk-space-specific hint when the journal's failure reason names
    /// an `insufficientDiskSpace` shortfall, so the user knows freeing
    /// space — not retrying — is the fix.
    public nonisolated static func detailText(for journal: MigrationJournal) -> String {
        let operation = journal.operation.map(operationDescription) ?? "the previous sync change"
        if journal.failureReason?.contains("insufficientDiskSpace") == true {
            return String(localized: "Lillist couldn't finish \(operation) because the device is low on storage. Free up some space, then try again — your data is safe in the backup we made before the change.", bundle: .module)
        }
        return String(localized: "Lillist couldn't finish \(operation). Restore from the backup we made before the change, or try again.", bundle: .module)
    }
```

  and change `operationDescription` from an instance method to a matching `nonisolated static` so the static helper can call it. Replace (current lines 65–72):

```swift
    private func operationDescription(_ op: ModeTransitionOp) -> String {
        switch op {
        case .replaceICloudWithLocal: return "replacing iCloud with this device's data"
        case .replaceLocalWithICloud: return "replacing this device's data with iCloud"
        case .syncFirstThenDisable: return "turning off iCloud Sync (after a final sync)"
        case .disableNow: return "turning off iCloud Sync"
        }
    }
```

  with:

```swift
    private nonisolated static func operationDescription(_ op: ModeTransitionOp) -> String {
        switch op {
        case .replaceICloudWithLocal: return "replacing iCloud with this device's data"
        case .replaceLocalWithICloud: return "replacing this device's data with iCloud"
        case .syncFirstThenDisable: return "turning off iCloud Sync (after a final sync)"
        case .disableNow: return "turning off iCloud Sync"
        }
    }
```

- [ ] **Step 4: Run the test, expect pass** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI --filter SyncMigrationRecoverySheetTests`. Expected: 2 tests passing. Then confirm the new localized string is captured by the catalog (it is extracted at build from the `String(localized:bundle:.module)` call): `cd /Volumes/Code/mikeyward/Lillist && grep -c "low on storage" Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift` — expect `1`. (The `.xcstrings` catalog auto-extracts on the next LillistUI build; no manual catalog edit is required because the key is a literal in source.)

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add Packages/LillistUI/Sources/LillistUI/Sync/SyncMigrationRecoverySheet.swift \
        Packages/LillistUI/Tests/LillistUITests/SyncMigrationRecoverySheetTests.swift
git commit -m "feat(ui): recovery sheet explains low-storage migration failures"
```

---

## Task 9: Full-suite verification + engineering note

**Files:**
- Modify `docs/engineering-notes.md` (append one entry).

- [ ] **Step 1: Run the full LillistCore suite** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -20`. Expected: all tests pass, including the new `DiskSpaceProbeTests`, `LillistErrorDiskSpaceTests`, the three new `QuarantineManagerTests`, and the one new `MigrationCoordinatorTests` disk-full case (plus the pre-existing `MigrationRecoveryTests` `restoreFromBackup` coverage, unchanged). Zero warnings (warnings-as-errors on the source target).

- [ ] **Step 2: Run the full LillistUI suite** — `cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI 2>&1 | tail -20`. Expected: all tests pass including `SyncMigrationRecoverySheetTests`.

- [ ] **Step 3: Build the iOS app target unsigned to confirm the new strings/types compile in the app shell** — `cd /Volumes/Code/mikeyward/Lillist && xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-iOS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -10`. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Append the engineering note** — add this entry to the end of `docs/engineering-notes.md` (read the file first to match its heading style and append a new dated section):

```markdown
## Recovery pre-flight: disk-space check lives in QuarantineManager.copyStore, not the coordinator

The destructive sync-mode swap's only recovery anchor is the quarantine
copy of the live SQLite store. A copy that runs out of room mid-write is
worse than no copy — so `QuarantineManager.copyStore(at:)` now runs a
**pre-flight** disk-space check (via an injectable `DiskSpaceProbing`)
and throws `LillistError.insufficientDiskSpace` *before touching any
file*. It requires `2×` the live footprint (`quarantineHeadroomFactor`)
to cover source+copy coexistence plus WAL-checkpoint inflation. The
check lives in `copyStore` (not the move-based `quarantineStore`)
because that is the method `runMigration` calls — a check in
`quarantineStore` would never fire during a migration.

Two ordering invariants a future refactor must preserve:

1. In `MigrationCoordinator.runMigration` the merged step order is
   precondition → `reconfigure` (step 4) → `copyStore` (step 5) →
   CloudKit zone erase (step 6). The disk check is inside `copyStore`
   (step 5), so a shortfall aborts before the irreversible erase. Do
   not reorder. NOTE: because `reconfigure` (step 4) precedes the copy,
   a disk-shortfall abort leaves the sync mode **already flipped to the
   target** — the recovery sheet's "Try Again" is what re-runs the now
   partially-applied swap; the user must free space first.
2. The check uses `volumeAvailableCapacityForImportantUsageKey` (honest
   "space the OS would free for a real write"), not the raw
   `.volumeAvailableCapacityKey`.

Residual: a `PRAGMA wal_checkpoint(TRUNCATE)` around `copyStore` would
shrink the WAL before the copy and tighten the 2× headroom estimate. It
is **not** implemented here — recorded as a known follow-up so a future
contributor doesn't assume the copy already checkpoints.

`restoreFromBackup` is covered by ungated `swift test` cases in
`MigrationRecoveryTests.swift` (the `test-2` gap, already closed before
this plan). Its happy-path test keeps `previousMode == host.currentMode`
so `reconfigure` is a no-op early-return and the test doesn't need a real
bundle id (`liveSwapAllowed`).
```

- [ ] **Step 5: Commit** —
```bash
cd /Volumes/Code/mikeyward/Lillist
git add docs/engineering-notes.md
git commit -m "docs: record disk-space pre-flight + restoreFromBackup coverage gotchas"
```

---

## Self-review checklist

- [ ] **Critic blind spot #5 (thin data-loss/recovery story)** — covered by Task 2 (`DiskSpaceProbe` seam), Task 3 (pre-flight free-space check inside `copyStore` before the recovery copy, failing clearly when insufficient), Task 4 (ordering pinned ahead of the irreversible erase), Task 5 (coordinator-level disk-full abort test), Task 8 (user-visible recovery copy explaining a low-storage failure).
- [ ] **`test-2` (`restoreFromBackup` untested)** — already closed: `MigrationRecoveryTests.swift` covers happy path, no-backup `storeUnavailable`, recorded-folder, legacy fallback, and the secondary-write-failure masking case. This plan adds no `restoreFromBackup` coverage (Tasks 6–7 removed).
- [ ] **Disk-space-insufficient path tested** — Task 3 (`QuarantineManager.copyStore` unit), Task 5 (`MigrationCoordinator` integration: throws, journal `.failed`, eraser never called, store not copied; mode reflects post-reconfigure state).
- [ ] **Successful-restore path tested** — pre-existing in `MigrationRecoveryTests.swift` (happy path).
- [ ] **Strengths preserved** — no change to the DTO boundary (new `DiskSpaceProbe` returns `Int64`, not `NSManagedObject`); no change to the synchronous AsyncStream registration; `Calendar`-based date math untouched; the new pure helper in Task 8 is `nonisolated static` per the MainActor-ripple rule; `QuarantineManager` stays filesystem-only and never opens Core Data.
- [ ] **No `.xcdatamodel` edits** — this plan adds no Core Data entities; the mtime touch ritual is not needed.
- [ ] **Conventional commits, small focused commits** — seven commits (Tasks 1–5, 8, 9), one per task, all `feat`/`test`/`docs` scoped.
- [ ] **Cross-plan coordination** — `QuarantineManager.swift` and `MigrationCoordinator.swift` are shared hotspots with store-swap-safety (Wave 1, merged) and migration-adjacent-correctness; this plan builds on the merged copy-not-move quarantine (`copyStore`), the reordered `runMigration` (reconfigure-before-copy), and the `PersistenceReconfiguring` seam (used in Task 5's `FakePersistenceReconfigurer` injection). Re-Read `runMigration` against the latest waves' handoffs before editing.
