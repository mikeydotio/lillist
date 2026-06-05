# Crash-Reporter Privacy Hardening Implementation Plan

> **📍 STATUS — ✅ MERGED — Wave 5 (commits `4dc1f96`..`5df296c`, 2026-06-05).** Closed redact-1, redact-5, canary-4, test-6. LillistCore 808 → 819 Swift-Testing tests, warning-free (verified green `--no-parallel`). Adversarially reviewed (spec + regression no findings; 3 INFO security observations recorded in the Wave-5 handoff). **One deviation from the printed plan**: Task 1 uses a capture-group regex `(title=)…` → `$1<redacted>` (not the bare lowercase literal template, which would lowercase the key and fail the plan's own Task-1 test + Task-5 golden); Task 7's stress test needs `try await withThrowingTaskGroup`. See `docs/superpowers/handoffs/wave-5.md`.
>
> Part of the **Foundation Hardening** program. **Single source of truth for progress, wave order, and cross-plan coordination:** [`2026-05-29-foundation-hardening-index.md`](2026-05-29-foundation-hardening-index.md). New to this project? Read the index first, then the review ([`docs/reviews/2026-05-28-foundation-review.md`](../../reviews/2026-05-28-foundation-review.md)) for *why* this work exists, then `CLAUDE.md` for conventions + build/test commands. Execute task-by-task with `superpowers:subagent-driven-development`.
>
> **Pre-flight (run before any edit):** Confirm Waves 1–4 are on `main` (`git log --oneline main | head -20`). Read `docs/superpowers/handoffs/wave-4.md`. Re-Read every file you touch and anchor by code **structure**, not line number — each wave shifts the shared hotspot files. On completion, write `docs/superpowers/handoffs/wave-5.md`.
>
> This lane is fully isolated: it touches only the `CrashReporting/` source and test files (`LogRedactor.swift`, `CrashReporter.swift`, `LogRedactorTests.swift`, `CrashReporterFlowTests.swift`) plus `docs/engineering-notes.md`. None of those overlap the shared store/sync/migration hotspots reshaped by Waves 1–4, so this plan's findings (redact-1, redact-5, canary-4, test-6) are wholly unaddressed by prior waves.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the crash-reporter PII leaks (case-sensitive redaction, container/temp-path gaps, brittle key=value passes), correct the canary self-PID disambiguation against PID recycling, and land adversarial golden fixtures plus the missing BreadcrumbBuffer concurrency and transport/fetcher error-path tests.

**Architecture:** `LogRedactor` is a pure-function ordered list of `NSRegularExpression` redaction passes; we tighten the existing passes (add `.caseInsensitive` to the key=value passes, make the container-hex class case-insensitive, generalize the iOS container pass to the App-Group shared subtree, add a temp-path pass) without changing the public surface. `CrashReporter.detectAndPrepare()` currently filters a self-written canary by PID equality alone, which is unsafe because the OS recycles PIDs; we add a `startedAt` recency check so a recycled-PID prior crash is still surfaced. All behavior changes land behind adversarial golden fixtures and Swift Testing suites that match the existing `CrashReporting/` test conventions.

**Tech Stack:** Swift 6.2, Foundation `NSRegularExpression`, Swift Testing (`import Testing`, `@Test`/`#expect`, `@Suite`), `Bundle.module` `.copy`-bundled `Fixtures/`, `swift test --package-path Packages/LillistCore`.

**Source findings:** redact-1, redact-5, canary-4, test-6 (review §"Prioritized roadmap" item 12, P2).

---

## File Structure

### Modify

- `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift` — add `.caseInsensitive` to the three `key=value` passes (redact-1); make the iOS-container hex character class case-insensitive and generalize the path prefix to the App-Group `Shared/AppGroup` subtree (redact-1); add a temp-directory path pass for `/private/var/folders`, `/var/folders`, `/tmp` (redact-5/redact-1); update the doc comment to state the single-token key=value limitation honestly.
- `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift` — change `detectAndPrepare()` so a prior canary is suppressed only when it is *both* same-PID *and* recent (within a small launch window of `now()`), so a recycled-PID real crash is still surfaced (canary-4); correct the docstring's false "PIDs never repeat / always different" claim.

### Create (test fixtures — auto-bundled by existing `.copy("CrashReporting/Fixtures")`)

- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.txt` — adversarial raw input: mixed-case keys, multi-word/quoted values, lowercase container UUIDs, App-Group shared subtree path, temp paths.
- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.expected.txt` — the exact redacted golden output.

### Create (tests)

- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferStressTests.swift` — TaskGroup concurrent-record stress test asserting the actor never loses an entry and honors capacity (test-6).
- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterErrorPathTests.swift` — throwing-transport and throwing-fetcher error propagation tests for `CrashReporter.submit` (test-6).

### Modify (tests)

- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift` — add the `adversarial` golden test (redact-1, redact-5) plus inline mixed-case / temp-path / lowercase-container assertions.
- `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift` — add a recycled-PID-with-old-`startedAt` regression test asserting the prior crash IS surfaced, and a same-PID-recent test asserting it is NOT (canary-4).

### Modify (docs)

- `docs/engineering-notes.md` — append one entry on the redactor's single-token key=value limitation and the canary PID-recycling rationale.

---

## Task 1: Make key=value redaction passes case-insensitive (redact-1)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift` (append a test after the `tagNames()` test, currently around line 47).
- Modify `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift` (the three key=value passes, currently lines 47–49).

- [ ] **Step 1: Write the failing test** — append this `@Test` inside `LogRedactorTests` (after the `tagNames()` test at line 47), matching the existing Swift Testing style:

```swift
    @Test("key=value redaction is case-insensitive on the key")
    func keyValue_caseInsensitive() {
        // redact-1: framework/third-party log lines capitalize keys
        // inconsistently. A `Title=` / `NOTES=` / `Tag=` key must redact
        // the same as the lowercase form, or PII leaks on mixed-case input.
        #expect(LogRedactor.redact("Title=Secret") == "Title=<redacted>")
        #expect(LogRedactor.redact("NOTES=Private") == "NOTES=<redacted>")
        #expect(LogRedactor.redact("Tag=Work") == "Tag=<redacted>")
    }
```

- [ ] **Step 2: Run the test, expect failure**

```bash
swift test --package-path Packages/LillistCore --filter "key=value redaction is case-insensitive on the key"
```

Expected failure — the value after the capitalized key survives, e.g.:
`Expectation failed: (LogRedactor.redact("Title=Secret") → "Title=Secret") == "Title=<redacted>"`

- [ ] **Step 3: Implement the minimal change** — in `LogRedactor.swift`, replace the three key=value `Pass` entries (currently lines 47–49) so each passes `options: .caseInsensitive`. Replace exactly:

```swift
            // Defense-in-depth key=value forms (whitespace-delimited).
            make(#"title=[^\s\n]*"#, "title=<redacted>"),
            make(#"notes=[^\s\n]*"#, "notes=<redacted>"),
            make(#"tag=[^\s\n]*"#, "tag=<redacted>"),
```

with:

```swift
            // Defense-in-depth key=value forms (whitespace-delimited).
            // Case-insensitive on the key: framework/third-party log lines
            // capitalize keys inconsistently (`Title=`, `NOTES=`). The
            // replacement template lowercases the key deliberately so the
            // redacted form is canonical regardless of the input casing.
            // Single-token only by design — multi-word/unwrapped PII is the
            // job of the wrapped-marker passes above; see the type comment.
            make(#"title=[^\s\n]*"#, "title=<redacted>", options: .caseInsensitive),
            make(#"notes=[^\s\n]*"#, "notes=<redacted>", options: .caseInsensitive),
            make(#"tag=[^\s\n]*"#, "tag=<redacted>", options: .caseInsensitive),
```

- [ ] **Step 4: Run the test, expect pass**

```bash
swift test --package-path Packages/LillistCore --filter LogRedactor
```

Expected: all `LogRedactor` tests pass, including `key=value redaction is case-insensitive on the key`, e.g. `Suite "LogRedactor" passed`.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift
git commit -m "fix(crash): make key=value redaction passes case-insensitive

Mixed-case log keys (Title=, NOTES=) bypassed the lowercase-only
redaction passes, leaking PII. Add .caseInsensitive to the three
key=value passes. Closes redact-1 (partial)."
```

---

## Task 2: Make container-path redaction case-insensitive and cover the App-Group shared subtree (redact-1)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift` (append after the test added in Task 1).
- Modify `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift` (the iOS container path pass, currently line 58).

- [ ] **Step 1: Write the failing test** — append this `@Test` inside `LogRedactorTests`:

```swift
    @Test("iOS container paths redact with lowercase hex and in the App-Group subtree")
    func containerPaths_caseInsensitiveAndAppGroup() {
        // redact-1: the container path pass used an uppercase-only hex
        // class [A-Z0-9-], so a lowercase-UUID Data container leaked its
        // path prefix and the bytes after the UUID; and it only matched
        // the `.../Data/Application/` subtree, not the App-Group
        // `.../Shared/AppGroup/` subtree where the shared store lives.
        let lowerData =
            "/var/mobile/Containers/Data/Application/deadbeef-0000-1111-2222-333344445555/Library/x.png"
        #expect(LogRedactor.redact(lowerData) == "<path>")
        let appGroup =
            "/var/mobile/Containers/Shared/AppGroup/aaaa1111-2222-3333-4444-555566667777/db.sqlite"
        #expect(LogRedactor.redact(appGroup) == "<path>")
    }
```

- [ ] **Step 2: Run the test, expect failure**

```bash
swift test --package-path Packages/LillistCore --filter "iOS container paths redact with lowercase hex and in the App-Group subtree"
```

Expected failure — the lowercase-hex Data path is only partially redacted (`/var/mobile/Containers/Data/Application/<uuid>/Library/x.png`) and the App-Group path is `/var/mobile/Containers/Shared/AppGroup/<uuid>/db.sqlite`, neither equal to `<path>`.

- [ ] **Step 3: Implement the minimal change** — in `LogRedactor.swift`, replace the single iOS-container pass (currently line 58):

```swift
            make(#"/var/mobile/Containers/Data/Application/[A-Z0-9-]+(?:/(?:[^\s]|\s(?=[A-Z][a-z]))*)?"#, "<path>"),
```

with a pass that (a) matches both the `Data/Application` and `Shared/AppGroup` subtrees and (b) accepts lowercase hex:

```swift
            // iOS sandbox + App-Group containers. The UUID segment is
            // hex-with-dashes in *either* case (real container names are
            // uppercase, but synced/imported/third-party log text is not
            // guaranteed to be), so the class is [0-9A-Fa-f-], not the
            // uppercase-only form. Both the per-app `Data/Application`
            // subtree and the shared `Shared/AppGroup` subtree (where the
            // shared store and canary live) are covered.
            make(#"/var/mobile/Containers/(?:Data/Application|Shared/AppGroup)/[0-9A-Fa-f-]+(?:/(?:[^\s]|\s(?=[A-Z][a-z]))*)?"#, "<path>"),
```

- [ ] **Step 4: Run the test, expect pass**

```bash
swift test --package-path Packages/LillistCore --filter LogRedactor
```

Expected: all `LogRedactor` tests pass, including the new container-path test.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift
git commit -m "fix(crash): redact lowercase container hex and App-Group subtree

The iOS container path pass used an uppercase-only hex class and only
matched Data/Application, so lowercase-UUID containers and the shared
App-Group store path leaked. Use a case-insensitive hex class and an
alternation over Data/Application | Shared/AppGroup. Closes redact-1
(partial)."
```

---

## Task 3: Add a temp-directory path redaction pass (redact-5 / redact-1)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift` (append after the Task 2 test).
- Modify `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift` (add a pass and a comment to the `passes` array).

- [ ] **Step 1: Write the failing test** — append this `@Test` inside `LogRedactorTests`:

```swift
    @Test("Temp-directory paths are redacted")
    func tempPaths_redacted() {
        // redact-5: NSTemporaryDirectory / FileManager temp URLs surface
        // in log text (attachment staging, export scratch files) and
        // contain a user-scoped DARWIN_USER_TEMP_DIR token. None of the
        // existing /Users, /var/mobile, or ~ passes match them.
        #expect(
            LogRedactor.redact("saved to /private/var/folders/ab/cd12/T/temp.png") == "saved to <path>"
        )
        #expect(
            LogRedactor.redact("saved to /var/folders/ab/cd12/T/temp.png") == "saved to <path>"
        )
        #expect(LogRedactor.redact("scratch /tmp/scratch.dat") == "scratch <path>")
    }
```

- [ ] **Step 2: Run the test, expect failure**

```bash
swift test --package-path Packages/LillistCore --filter "Temp-directory paths are redacted"
```

Expected failure — temp paths pass through unmodified, e.g. `("saved to /private/var/folders/ab/cd12/T/temp.png") == "saved to <path>"` fails.

- [ ] **Step 3: Implement the minimal change** — in `LogRedactor.swift`, add the temp-path pass to the `passes` array immediately after the `~/...` path pass (currently line 59, `make(#"~/(?:[^\s]|\s(?=[A-Z][a-z]))*"#, "<path>"),`). Insert this new pass directly after it:

```swift
            make(#"~/(?:[^\s]|\s(?=[A-Z][a-z]))*"#, "<path>"),
            // Temp-directory paths. NSTemporaryDirectory resolves to
            // `/private/var/folders/<hash>/<hash>/T/...` (the `/private`
            // prefix is optional in symlink-resolved forms), and scratch
            // files land under `/tmp`. These carry a user-scoped
            // DARWIN_USER_TEMP_DIR token; redact the whole path. Same
            // capitalized-space lookahead as the other path passes so a
            // `.../Application Support`-style component is consumed too.
            make(#"(?:/private)?/var/folders/(?:[^\s]|\s(?=[A-Z][a-z]))*"#, "<path>"),
            make(#"/tmp/(?:[^\s]|\s(?=[A-Z][a-z]))*"#, "<path>"),
```

- [ ] **Step 4: Run the test, expect pass**

```bash
swift test --package-path Packages/LillistCore --filter LogRedactor
```

Expected: all `LogRedactor` tests pass, including `Temp-directory paths are redacted`.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift
git commit -m "fix(crash): redact temp-directory paths

NSTemporaryDirectory (/private/var/folders, /var/folders) and /tmp
scratch paths carry a user-scoped token and were not matched by any
existing path pass. Add two temp-path passes. Closes redact-5 (partial)."
```

---

## Task 4: Document the single-token key=value limitation in the type comment (redact-5)

**Files:**
- Modify `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift` (the type-level doc comment, currently lines 3–9).

This task has no behavior change, so it is documentation-only (no TDD cycle). The adversarial golden fixture in Task 5 is the executable proof of the documented limitation.

- [ ] **Step 1: Update the type doc comment** — replace the existing type doc comment (currently lines 3–9):

```swift
/// Pure-function redaction over raw log text.
///
/// Applies the redaction passes enumerated in the Plan 9 design,
/// in fixed order. Each pass is idempotent. Design Section 8
/// requires that task titles, notes, journal bodies, tag names,
/// file paths under user dirs, email addresses, and UUIDs are all
/// stripped before any log text leaves the device.
```

with:

```swift
/// Pure-function redaction over raw log text.
///
/// Applies the redaction passes enumerated in the Plan 9 design,
/// in fixed order. Each pass is idempotent. Design Section 8
/// requires that task titles, notes, journal bodies, tag names,
/// file paths under user dirs, email addresses, and UUIDs are all
/// stripped before any log text leaves the device.
///
/// **PII must be wrapped, not bare.** The authoritative PII passes are
/// the wrapped-marker forms (`<title>…</title>`, `<notes>…</notes>`,
/// `<journal>…</journal>`, `<tag>…</tag>`), which redact arbitrary
/// content *including spaces* via a non-greedy `[\s\S]*?`. The
/// `key=value` passes are single-token defense-in-depth only: they stop
/// at the first whitespace, so a bare multi-word or quoted value
/// (`title=Buy milk`) is **not** fully redacted. Any code that logs
/// user content must therefore wrap it in a marker; do not rely on the
/// `key=value` passes to catch unwrapped multi-word PII. The adversarial
/// golden fixture (`raw-logs-adversarial`) pins this contract.
```

- [ ] **Step 2: Verify it compiles**

```bash
swift build --package-path Packages/LillistCore 2>&1 | tail -5
```

Expected: `Build complete!` (warnings-as-errors clean; a doc-comment-only change cannot introduce a warning).

- [ ] **Step 3: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift
git commit -m "docs(crash): document the single-token key=value redaction limit

State explicitly that the key=value passes are single-token
defense-in-depth and that arbitrary/multi-word PII must be wrapped in a
marker. Closes redact-5 (the 'stop emitting bare key=value PII' half)."
```

---

## Task 5: Land the adversarial golden fixture (redact-1, redact-5)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.txt`.
- Create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.expected.txt`.
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift` (add a `@Test` using the existing `goldenTest` helper).

The fixtures are auto-bundled by the existing `.copy("CrashReporting/Fixtures")` entry in `Packages/LillistCore/Package.swift` (line 37) — no manifest change needed.

> The `.expected.txt` content below is the exact output of the redactor **after Tasks 1–3 land**. It honestly records the documented limitation from Task 4: the bare multi-word `title=Buy milk and bread` line redacts only the first token (`title=<redacted> milk and bread`), while the *wrapped* equivalent is fully redacted. This is the executable proof of the contract, not a bug to "fix" in this plan.

- [ ] **Step 1: Write the failing test** — append this `@Test` inside `LogRedactorTests`:

```swift
    @Test("Adversarial input: mixed-case keys, quoted/multi-word values, lowercase containers, temp paths")
    func adversarial() throws { try goldenTest("raw-logs-adversarial") }
```

- [ ] **Step 2: Create the raw fixture** — write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.txt` with exactly this content (final newline included):

```
2026-05-12 10:00:01 [TaskStore] updated Title=Pickup to closed
2026-05-12 10:00:02 [TaskStore] updated NOTES=Confidential to open
2026-05-12 10:00:03 [TagStore] linked Tag=Work to task
2026-05-12 10:00:04 [TaskStore] created <title>Buy groceries on the way home</title>
2026-05-12 10:00:05 [TaskStore] updated title=Buy milk and bread to closed
2026-05-12 10:00:06 [Attach] saved to /var/mobile/Containers/Data/Application/deadbeef-0000-1111-2222-333344445555/Library/x.png
2026-05-12 10:00:07 [Sync] opened /var/mobile/Containers/Shared/AppGroup/aaaa1111-2222-3333-4444-555566667777/db.sqlite
2026-05-12 10:00:08 [Attach] staged /private/var/folders/ab/cd12/T/temp.png
2026-05-12 10:00:09 [Export] scratch /tmp/lillist-export.json
2026-05-12 10:00:10 [Account] iCloud account Mikey.Ward@Example.COM active
```

- [ ] **Step 3: Create the expected fixture** — write `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.expected.txt` with exactly this content (final newline included):

```
2026-05-12 10:00:01 [TaskStore] updated Title=<redacted> to closed
2026-05-12 10:00:02 [TaskStore] updated NOTES=<redacted> to open
2026-05-12 10:00:03 [TagStore] linked Tag=<redacted> to task
2026-05-12 10:00:04 [TaskStore] created <title><redacted></title>
2026-05-12 10:00:05 [TaskStore] updated title=<redacted> milk and bread to closed
2026-05-12 10:00:06 [Attach] saved to <path>
2026-05-12 10:00:07 [Sync] opened <path>
2026-05-12 10:00:08 [Attach] staged <path>
2026-05-12 10:00:09 [Export] scratch <path>
2026-05-12 10:00:10 [Account] iCloud account <email> active
```

- [ ] **Step 4: Run the test, expect pass**

```bash
swift test --package-path Packages/LillistCore --filter LogRedactor
```

Expected: all `LogRedactor` tests pass, including `Adversarial input: mixed-case keys, quoted/multi-word values, lowercase containers, temp paths`. If it fails with a `Redaction mismatch` diff, the `GOT:` block in the failure message is the source of truth — copy it verbatim into `.expected.txt` (the redactor is the spec; the golden file must match its real output), then re-run. Do **not** weaken a redaction pass to satisfy a stale expected file.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.txt \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/Fixtures/raw-logs-adversarial.expected.txt \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/LogRedactorTests.swift
git commit -m "test(crash): add adversarial redaction golden fixture

Pins mixed-case keys, quoted/multi-word values, lowercase container
UUIDs, the App-Group shared subtree, temp paths, and mixed-case emails.
The multi-word key=value line documents the single-token limitation.
Closes redact-1, redact-5 (golden coverage)."
```

---

## Task 6: Disambiguate the canary self-PID filter with startedAt (canary-4)

**Files:**
- Modify `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift` (add two `@Test`s after `selfPidCanary_isNotPending` at line 76).
- Modify `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift` (`detectAndPrepare()` at lines 64–80, plus the docstring at lines 67–73).

**Background (verified against the code):** `detectAndPrepare()` currently suppresses any prior canary whose `pid == currentPID`, justified by the docstring claim that "Cross-process canaries (real prior crashes) have a different `pid`, so the filter is safe." That claim is false: the OS recycles PIDs, so a real prior crash can carry the *same* PID as the current process and be silently swallowed. The fix uses `startedAt`: a *self-write* (pre-arm during this same launch) has `startedAt ≈ now()`, whereas a *recycled-PID prior crash* has an `startedAt` from a previous, older launch. We suppress only when same-PID **and** the canary's `startedAt` is within a short launch window of `now()`.

The reporter already holds an injectable `now: @Sendable () -> Date` clock (line 23), so the recency check is deterministic in tests.

- [ ] **Step 1: Write the failing tests** — insert these two `@Test`s into `CrashReporterFlowTests` immediately after the `selfPidCanary_isNotPending()` test (after line 76). The existing `makeReporter` helper pins the reporter clock to `Date(timeIntervalSince1970: 1_000_000)` (line 29), so use that as "now":

```swift
    @Test("Recycled-PID prior crash with an old startedAt IS surfaced")
    func recycledPidOldStart_isPending() async throws {
        // canary-4: the OS recycles PIDs. A real prior crash can carry the
        // same PID as this process. Suppressing purely on PID equality
        // would silently swallow that crash. The prior canary's startedAt
        // is from an *earlier* launch, so it is far from this run's now().
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        // reporter "now" is 1_000_000; plant a same-PID canary that started
        // a full hour earlier — unmistakably a prior launch.
        let recycled = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(timeIntervalSince1970: 1_000_000 - 3600),
            buildVersion: "0.9",
            hostname: "old"
        )
        try CanaryFile(url: url).writeFresh(recycled)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == recycled)
    }

    @Test("Self-pre-armed canary with a recent startedAt is NOT surfaced")
    func selfPidRecentStart_isNotPending() async throws {
        // canary-4: a pre-arm earlier in *this* launch has startedAt ≈ now,
        // so it must still be filtered out even though PIDs can recycle.
        let recording = RecordingTransport()
        let (reporter, url) = await makeReporter(transport: recording)
        defer { try? FileManager.default.removeItem(at: url) }
        let selfRecent = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(timeIntervalSince1970: 1_000_000 - 1), // 1s ago
            buildVersion: "1.0 (1)",
            hostname: "host"
        )
        try CanaryFile(url: url).writeFresh(selfRecent)
        let pending = try await reporter.detectAndPrepare()
        #expect(pending == nil)
    }
```

- [ ] **Step 2: Run the tests, expect failure**

```bash
swift test --package-path Packages/LillistCore --filter "Recycled-PID prior crash with an old startedAt IS surfaced"
```

Expected failure — current code suppresses on PID alone, so the recycled prior crash is dropped: `Expectation failed: (pending → nil) == (recycled → CrashCanary(...))`.

- [ ] **Step 3: Implement the minimal change** — in `CrashReporter.swift`, replace the entire `detectAndPrepare()` method including its doc comment (currently lines 64–80):

```swift
    /// On launch, return a `CrashCanary` if the previous run did
    /// not exit cleanly. Replaces the canary with a fresh one for
    /// the current run.
    ///
    /// A canary whose `pid` matches the current process is a
    /// self-write from earlier in this same launch — possible if a
    /// lifecycle observer (iOS foreground transition) armed the
    /// canary before `detectAndPrepare` ran, or if a caller pre-armed
    /// via `start()`. Cross-process canaries (real prior crashes)
    /// have a different `pid`, so the filter is safe.
    public func detectAndPrepare() throws -> CrashCanary? {
        let prior = try canaryFile.readIfPresent()
        try start()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let prior, prior.pid == currentPID { return nil }
        return prior
    }
```

with:

```swift
    /// On launch, return a `CrashCanary` if the previous run did
    /// not exit cleanly. Replaces the canary with a fresh one for
    /// the current run.
    ///
    /// A canary whose `pid` matches the current process *and* whose
    /// `startedAt` is within `selfWriteWindow` of `now()` is a
    /// self-write from earlier in this same launch — possible if a
    /// lifecycle observer (iOS foreground transition) armed the
    /// canary before `detectAndPrepare` ran, or if a caller pre-armed
    /// via `start()`. PID alone is *not* sufficient: the OS recycles
    /// PIDs, so a genuine prior crash can carry the same PID. The
    /// `startedAt` recency check distinguishes a same-launch pre-arm
    /// (recent) from a recycled-PID prior crash (an earlier launch),
    /// so a real crash is never silently swallowed.
    public func detectAndPrepare() throws -> CrashCanary? {
        let prior = try canaryFile.readIfPresent()
        try start()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let prior,
           prior.pid == currentPID,
           abs(prior.startedAt.timeIntervalSince(now())) < Self.selfWriteWindow {
            return nil
        }
        return prior
    }
```

Then add the window constant as a `private static let` on the actor. Insert it directly after the stored properties, immediately before the `public init(` declaration (currently line 25):

```swift
    /// How recent a same-PID canary's `startedAt` must be to count as a
    /// pre-arm from *this* launch rather than a recycled-PID prior crash.
    /// 30 s comfortably covers app bootstrap + the first foreground
    /// transition while staying far below any realistic inter-launch gap.
    private static let selfWriteWindow: TimeInterval = 30
```

- [ ] **Step 4: Run the tests, expect pass**

```bash
swift test --package-path Packages/LillistCore --filter CrashReporter
```

Expected: all `CrashReporter flow` tests pass — including the existing `selfPidCanary_isNotPending` (its planted canary uses `startedAt: Date(timeIntervalSince1970: 999_000)`, which is `1000` seconds before the reporter's `now()` of `1_000_000`, i.e. *outside* the 30 s window — so with the new logic it would now be surfaced, **breaking that test**). Therefore this step also requires updating that existing test so its self-write is recent. See Step 4a.

- [ ] **Step 4a: Fix the pre-existing self-pid test to use a recent startedAt** — the existing `selfPidCanary_isNotPending()` test (lines 59–76) planted a self-canary with `startedAt: Date(timeIntervalSince1970: 999_000)`, which under the old PID-only logic was suppressed regardless of time. Under the new logic that timestamp is 1000 s before `now()` and would (correctly) be surfaced as a recycled-PID crash. Update only the `startedAt` of that planted canary to be recent. Replace exactly:

```swift
        let selfCanary = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "1.0 (1)",
            hostname: "host"
        )
```

with:

```swift
        let selfCanary = CrashCanary(
            pid: ProcessInfo.processInfo.processIdentifier,
            // Recent startedAt (matches the reporter's pinned now of
            // 1_000_000) so it reads as a same-launch pre-arm, not a
            // recycled-PID prior crash. See canary-4.
            startedAt: Date(timeIntervalSince1970: 1_000_000),
            buildVersion: "1.0 (1)",
            hostname: "host"
        )
```

Then re-run:

```bash
swift test --package-path Packages/LillistCore --filter CrashReporter
```

Expected: all `CrashReporter flow` tests pass, including the two new tests and the updated `selfPidCanary_isNotPending`.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift \
        Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterFlowTests.swift
git commit -m "fix(crash): disambiguate self-pid canary by startedAt recency

The OS recycles PIDs, so suppressing a prior canary on PID equality
alone could silently swallow a real crash that happened to reuse this
process's PID. Suppress only when same-PID AND startedAt is within a
30s launch window of now(). Correct the false 'PIDs always differ'
docstring. Closes canary-4."
```

---

## Task 7: Add the BreadcrumbBuffer TaskGroup concurrency stress test (test-6)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferStressTests.swift`.

`BreadcrumbBuffer` is an `actor`; the review notes the crash-reporting lane has zero stress tests. Per CLAUDE.md ("add stress repetitions for any code that crosses actor boundaries") we add a high-iteration concurrent-record test using a `TaskGroup`. Match the existing `BreadcrumbBufferTests` framework exactly: `import Testing` + `@Suite` + `async`/`await`.

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferStressTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("BreadcrumbBuffer stress")
struct BreadcrumbBufferStressTests {
    /// Concurrently hammer the actor from many child tasks. The actor
    /// must serialize every `record` (no lost append, no over-count) and
    /// honor the 200-entry capacity. Run several outer repetitions so a
    /// rare interleaving has a chance to surface.
    @Test("Concurrent records never exceed capacity and never crash")
    func concurrentRecords_respectCapacity() async throws {
        for _ in 0..<20 {
            let buffer = BreadcrumbBuffer()
            await withThrowingTaskGroup(of: Void.self) { group in
                for i in 0..<1_000 {
                    group.addTask {
                        // Action strings are PII-clean verbs (no UUID,
                        // no "@", no "/") so record() never rejects.
                        try await buffer.record(action: "step.\(i)", success: i.isMultiple(of: 2))
                    }
                }
            }
            let snap = await buffer.snapshot()
            // 1_000 records into a 200-capacity ring: the buffer caps at
            // exactly 200 and never overflows or loses the invariant.
            #expect(snap.count == BreadcrumbBuffer.capacity)
        }
    }

    /// Records and snapshots interleaved concurrently. Each snapshot is a
    /// value copy, so it must never be larger than capacity regardless of
    /// when it is taken relative to the writers.
    @Test("Concurrent snapshots are always a bounded immutable copy")
    func concurrentSnapshots_bounded() async throws {
        let buffer = BreadcrumbBuffer()
        await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<500 {
                group.addTask {
                    try await buffer.record(action: "w.\(i)", success: true)
                    return 0
                }
            }
            for _ in 0..<500 {
                group.addTask {
                    await buffer.snapshot().count
                }
            }
            for try await observed in group {
                #expect(observed <= BreadcrumbBuffer.capacity)
            }
        }
    }
}
```

- [ ] **Step 2: Run the test, expect pass** — `BreadcrumbBuffer` is already a correct actor, so this codifies (does not fix) behavior. It is "expected to fail" only in the sense that it must exist; run it first to confirm it both compiles and passes:

```bash
swift test --package-path Packages/LillistCore --filter "BreadcrumbBuffer stress"
```

Expected: `Suite "BreadcrumbBuffer stress" passed`. If `concurrentRecords_respectCapacity` ever reports `snap.count` != 200, that is a real actor-isolation regression — stop and investigate before touching the test (do not relax the assertion).

- [ ] **Step 3: No implementation change needed** — the actor already serializes correctly; this task is pure test coverage. Skip to commit. (If Step 2 had failed on a count mismatch, the fix would belong to whoever introduced the regression, not this plan — `BreadcrumbBuffer` is in the review's "well-layered" list and must not be refactored away.)

- [ ] **Step 4: Run the full CrashReporting suite to confirm no interaction**

```bash
swift test --package-path Packages/LillistCore --filter CrashReporting 2>&1 | tail -5
```

Expected: the broader run passes (no test named exactly `CrashReporting`, so the `--filter` matches by substring across the crash suites); confirm no failures reported.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/BreadcrumbBufferStressTests.swift
git commit -m "test(crash): add BreadcrumbBuffer TaskGroup concurrency stress

20x 1000-way concurrent record() plus interleaved snapshot() asserting
the actor caps at capacity and every snapshot is a bounded immutable
copy. Closes test-6 (concurrency half)."
```

---

## Task 8: Add throwing transport + fetcher error-path tests (test-6)

**Files:**
- Create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterErrorPathTests.swift`.

The `submit` flow propagates errors from both `logFetcher.fetchRecentLines` and `transport.send`, but no test exercises the throwing paths. We add local throwing fakes (the existing `FakeLogFetcher`/`RecordingTransport` never throw) and assert error propagation. Match the `CrashReporterFlowTests` setup style (sandboxed `CanaryFile`, pinned `now`, `import Testing`).

- [ ] **Step 1: Write the failing test** — create `Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterErrorPathTests.swift`:

```swift
import Testing
import Foundation
@testable import LillistCore

@Suite("CrashReporter error paths")
struct CrashReporterErrorPathTests {
    /// Sentinel error the throwing fakes raise.
    private struct BoomError: Error, Equatable {}

    /// A transport whose `send` always throws.
    private actor ThrowingTransport: CrashReportTransport {
        private(set) var attempts = 0
        func send(_ report: CrashReport) async throws {
            attempts += 1
            throw BoomError()
        }
    }

    /// A fetcher whose `fetchRecentLines` always throws.
    private struct ThrowingLogFetcher: LogFetching {
        func fetchRecentLines(since: Date, subsystem: String) async throws -> [String] {
            throw BoomError()
        }
    }

    /// Build a reporter with injectable transport + fetcher.
    private func makeReporter(
        logFetcher: LogFetching,
        transport: CrashReportTransport
    ) -> (CrashReporter, URL) {
        let canaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canary-\(UUID()).json")
        let reporter = CrashReporter(
            canaryFile: CanaryFile(url: canaryURL),
            buildVersion: "1.0 (1)",
            osVersion: "macOS 15",
            deviceModel: "Mac",
            hostname: "host",
            logFetcher: logFetcher,
            breadcrumbs: BreadcrumbBuffer(),
            transport: transport,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        return (reporter, canaryURL)
    }

    @Test("A throwing transport propagates the error out of submit")
    func throwingTransport_propagates() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: FakeLogFetcher(lines: ["line"]),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        await #expect(throws: BoomError.self) {
            try await reporter.submit(
                decision: .send,
                description: nil,
                includeLogs: false,
                includeBreadcrumbs: false,
                pending: pending
            )
        }
        let attempts = await transport.attempts
        #expect(attempts == 1)
    }

    @Test("A throwing log fetcher propagates and never reaches the transport")
    func throwingFetcher_propagatesBeforeTransport() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: ThrowingLogFetcher(),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        await #expect(throws: BoomError.self) {
            try await reporter.submit(
                decision: .send,
                description: nil,
                includeLogs: true,             // forces the fetcher path
                includeBreadcrumbs: false,
                pending: pending
            )
        }
        // The fetcher threw first, so the transport must never be called.
        let attempts = await transport.attempts
        #expect(attempts == 0)
    }

    @Test("dontSend never touches a throwing transport")
    func dontSend_skipsThrowingTransport() async throws {
        let transport = ThrowingTransport()
        let (reporter, url) = makeReporter(
            logFetcher: FakeLogFetcher(lines: ["line"]),
            transport: transport
        )
        defer { try? FileManager.default.removeItem(at: url) }
        let pending = CrashCanary(
            pid: 1,
            startedAt: Date(timeIntervalSince1970: 999_000),
            buildVersion: "0.9",
            hostname: "old"
        )
        try await reporter.submit(
            decision: .dontSend,
            description: nil,
            includeLogs: true,
            includeBreadcrumbs: true,
            pending: pending
        )
        let attempts = await transport.attempts
        #expect(attempts == 0)
    }
}
```

- [ ] **Step 2: Run the tests, expect pass** — these assert the *existing* propagation contract (`submit` is `async throws` and `await`s both seams), so they should pass once compiled. Run:

```bash
swift test --package-path Packages/LillistCore --filter "CrashReporter error paths"
```

Expected: `Suite "CrashReporter error paths" passed` with all three tests passing. If `throwingFetcher_propagatesBeforeTransport` fails with `attempts == 1`, that is a real ordering bug (the fetcher error was swallowed and the transport still ran) — investigate `CrashReporter.submit` before adjusting the test.

- [ ] **Step 3: No implementation change needed** — `submit` already propagates via `try await`. This is pure error-path coverage; do not alter `CrashReporter.submit`.

- [ ] **Step 4: Run the full crash suite for regressions**

```bash
swift test --package-path Packages/LillistCore --filter CrashReporting 2>&1 | tail -5
```

Expected: no failures across the crash-reporting suites.

- [ ] **Step 5: Commit**

```bash
git add Packages/LillistCore/Tests/LillistCoreTests/CrashReporting/CrashReporterErrorPathTests.swift
git commit -m "test(crash): cover throwing transport and fetcher error paths

Add local throwing CrashReportTransport and LogFetching fakes; assert
submit propagates a transport error (1 attempt), propagates a fetcher
error before the transport runs (0 attempts), and never touches the
transport on dontSend. Closes test-6 (error-path half)."
```

---

## Task 9: Document the redaction limit and PID-recycling rationale in engineering notes

**Files:**
- Modify `docs/engineering-notes.md` (append a new dated entry at the end of the file).

This is append-only documentation per CLAUDE.md (a future contributor would otherwise re-derive both lessons the hard way: that the key=value passes are intentionally single-token, and why the canary filter cannot trust PID alone). No code change, no TDD cycle.

- [ ] **Step 1: Append the entry** — add this block at the very end of `docs/engineering-notes.md`, after whatever the current final entry is (the file's tail moves with each wave — re-Read the tail and append below it; do not anchor on a named entry), preserving the existing trailing content:

```markdown

## 2026-05-28 — Crash-reporter redaction is layered, and the canary can't trust PID alone

**Redaction: wrapped markers are authoritative; key=value is single-token
defense-in-depth.** `LogRedactor` runs an ordered list of regex passes.
The wrapped-marker passes (`<title>…</title>`, `<notes>`, `<journal>`,
`<tag>`) redact arbitrary content *including spaces* via a non-greedy
`[\s\S]*?`. The `key=value` passes (`title=…`, `notes=…`, `tag=…`) stop at
the first whitespace, so a bare multi-word value (`title=Buy milk`) is
**not** fully redacted — only the first token is. This is intentional: the
key=value passes exist purely as a backstop for accidental single-token
leaks; any code logging user content must wrap it in a marker. The
adversarial golden fixture
(`Tests/.../CrashReporting/Fixtures/raw-logs-adversarial.{txt,expected.txt}`)
pins this contract, including the deliberately-only-partially-redacted
multi-word line. Don't "fix" that fixture line by greedily extending the
key=value passes to end-of-line — that would over-redact legitimate
trailing log structure (` to closed`, ` to task`) and break the
human-readability the crash reports depend on.

The path/container passes use a capitalized-space lookahead
(`\s(?=[A-Z][a-z])`) so a path can swallow a literal-space component like
`Application Support`. The container/temp passes use a case-insensitive
hex class (`[0-9A-Fa-f-]`) and cover both the per-app `Data/Application`
subtree and the shared `Shared/AppGroup` subtree, plus
`/private/var/folders`, `/var/folders`, and `/tmp`. UUIDs are redacted
last so paths/emails are gone before the bare-UUID fallback runs.

**The canary cannot suppress a prior crash on PID equality alone.**
`CrashReporter.detectAndPrepare()` must ignore a canary it wrote *earlier
in this same launch* (a lifecycle pre-arm) without ignoring a *real* prior
crash. The original filter compared `pid` only, on the assumption that a
cross-process crash always has a different PID. That assumption is false:
the OS recycles PIDs, so a genuine prior crash can carry this process's
PID and would be silently swallowed. The fix adds a `startedAt` recency
check (same-PID **and** `startedAt` within a 30 s window of `now()` ⇒
treat as a same-launch pre-arm; otherwise surface it). The reporter's
injectable `now` clock makes this deterministic in tests. If you ever see
a real crash go unreported with a matching PID, this window is the first
place to look.
```

- [ ] **Step 2: Verify the entry rendered and the file is otherwise unchanged**

```bash
git diff --stat docs/engineering-notes.md
```

Expected: `docs/engineering-notes.md | NN ++++++++...` showing only insertions (no deletions).

- [ ] **Step 3: Commit**

```bash
git add docs/engineering-notes.md
git commit -m "docs(notes): record crash-redaction layering + canary PID-recycling

Append an engineering note explaining why the key=value redaction passes
are intentionally single-token, why the canary filter cannot trust PID
alone, and the rationale behind the 30s startedAt recency window."
```

---

## Task 10: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the complete LillistCore suite**

```bash
swift test --package-path Packages/LillistCore 2>&1 | tail -15
```

Expected: the full suite passes (the pre-existing 649+ tests plus the new crash-reporter tests), ending in `Test run with NNN tests in M suites passed`. Zero failures, zero unexpected.

- [ ] **Step 2: Confirm warnings-as-errors is clean**

```bash
swift build --package-path Packages/LillistCore 2>&1 | tail -5
```

Expected: `Build complete!` with no warning lines (LillistCore source builds under strict concurrency + warnings-as-errors).

- [ ] **Step 3: Confirm the working tree is clean (all work committed)**

```bash
git status --short
```

Expected: empty output (every change from Tasks 1–9 is committed).

---

## Self-review checklist

- **redact-1** (case-insensitive key=value passes + case-insensitive container hex + App-Group subtree) — closed by **Task 1** (`.caseInsensitive` on `title=`/`notes=`/`tag=`), **Task 2** (`[0-9A-Fa-f-]` hex class + `Data/Application|Shared/AppGroup` alternation), and pinned by the **Task 5** adversarial golden fixture.
- **redact-5** (stop relying on bare key=value PII; rely on wrapped-marker passes that handle spaces; temp-path pass) — closed by **Task 3** (temp-path passes for `/private/var/folders`, `/var/folders`, `/tmp`), **Task 4** (type-comment documenting the single-token limitation and the wrapped-marker contract), and pinned by the **Task 5** adversarial fixture (the multi-word key=value line and the wrapped equivalent).
- **canary-4** (disambiguate self-PID via `startedAt`; correct the false "PIDs never repeat" note) — closed by **Task 6** (same-PID **and** `startedAt`-recency suppression, corrected docstring, recycled-PID + recent-self regression tests) and documented in **Task 9**.
- **test-6** (BreadcrumbBuffer TaskGroup stress + throwing transport/fetcher error-path tests) — closed by **Task 7** (`BreadcrumbBufferStressTests`) and **Task 8** (`CrashReporterErrorPathTests`).

**Strengths preserved (not refactored away):** the `LogRedactor` pure-function ordered-pass design and idempotence are unchanged (only passes tightened); `BreadcrumbBuffer`'s actor isolation and synchronous-rejection API are untouched (Task 7 only adds coverage); `CrashReporter`'s injectable `now` clock is reused for deterministic canary tests; the `record(from:)`/DTO boundary and Sendable value types are unaffected; no `NSManagedObject` is involved anywhere in this plan.
