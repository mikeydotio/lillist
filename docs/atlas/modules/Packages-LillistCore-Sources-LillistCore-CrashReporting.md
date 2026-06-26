---
module: Packages/LillistCore/Sources/LillistCore/CrashReporting
summary: "Canary-based in-house crash reporter: detects crashes, redacts PII from logs, assembles opt-in user-mediated reports."
read_when: "Touching crash detection or log redaction"
sources:
  - path: "Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift"
    blob: 1903156bfc349c5fd5ab6ea58356e7f22cf20369
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift
    blob: 74efe7dff31af290939d779fcf47d49c583a50a2
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift
    blob: 81a5e9be1a41d4a0caaeec1c3f8ac171a0d2f82f
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift
    blob: 044dd9f1f3faea5f0d82d497493be73ff9feed6f
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift
    blob: ed24bc86615ecbc0ba4ab5b07a2830565cb72adb
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift
    blob: 0f8bd614f6f1960e4a52edb574b8c65df9ca0747
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift
    blob: adee929b22263f1fe25a2b36454e2103a21a17da
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift
    blob: 0aaab69bf29d3f1233860d00b0dc14b2a965ef7c
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift
    blob: 0b48fb534c9ec83985ba7f61822128f1103e1514
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift
    blob: cb4793e61bc5abc2a0fe8e401a72484c3bc312fd
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift
    blob: fdb21347e99f1aba3d1718cbfcf699687413377c
references_modules: [Packages-LillistCore-Sources-LillistCore-LinkPreview, Packages-LillistCore-Sources-LillistCore-Ordering, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore/CrashReporting

## Purpose

Implements an in-house, user-mediated crash reporter: a canary file is written on every launch and deleted on clean exit; its presence on the next launch proves the prior run crashed. The module then assembles a redacted, opt-in payload (OSLog lines through `LogRedactor`, action breadcrumbs from `BreadcrumbBuffer`) and hands it to a `CrashReportTransport` only when the user explicitly chooses to send. If this module vanished, the app would have no crash detection and no way to surface or report crashes to the developer without a third-party SDK.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Breadcrumb` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift:8` | Immutable Codable value type for one timestamped action verb; `action` must contain no IDs, paths, or emails — the buffer enforces this at record time, not here. |
| `BreadcrumbBuffer` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:10` | Actor-isolated ring buffer capped at 200 entries; `record` rejects UUIDs, emails, and paths; `snapshot` returns an independent copy callers may hold without retaining the actor. |
| `CanaryFile` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:7` | Sendable value type wrapping a canary URL; write/read/delete are synchronous throws; corrupt files are silently deleted on read so a poisoned write does not permanently block crash detection. |
| `CrashCanary` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift:8` | Sendable snapshot of a process identity at launch (pid, startedAt, buildVersion, hostname); persisted as ISO-8601 JSON and read on the next launch to bound the OSLog query window. |
| `CrashReport` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift:9` | Opt-in Codable payload; `logs` and `breadcrumbs` are nil unless the user kept the respective checkboxes — callers treat nil sections as absent, not empty. |
| `CrashReportTransport` | protocol | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:9` | Single-method Sendable delivery protocol; conformers must not transmit the report without explicit user action — the design Section 8 contract is user-mediated only. |
| `CrashReporter` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:7` | Actor owning the full crash lifecycle: arm canary on launch via `start`, detect stale canary via `detectAndPrepare`, assemble and dispatch redacted report via `submit` — all per design Section 8. |
| `CrashReporting` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift:7` | Namespace enum; its only member is `subsystemIdentifier` — the stable OSLog subsystem string used by `OSLogFetcher` and asserted in tests; must never change after first release. |
| `FileSaveTransport` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:25` | Writes a pretty-printed JSON `.lillistcrash` file atomically to `destination`; callers supply a user-chosen URL from a save panel — no upload or network contact occurs. |
| `LogFetching` | protocol | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:7` | Single-method Sendable protocol abstracting log retrieval; production conformer is `OSLogFetcher`; tests inject a fake to avoid `OSLogStore` sandbox permission requirements. |
| `LogRedactor` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:21` | Stateless caseless enum with one entry point `redact(_:)`; applies a fixed ordered pipeline of regex passes stripping titles, notes, paths, emails, and UUIDs — callers receive a redacted string or the original on empty input. |
| `OSLogFetcher` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:15` | Production `LogFetching` backed by `OSLogStore(scope: .currentProcessIdentifier)`; filters entries to the given `subsystem` and returns ISO-8601-prefixed composed messages. |
| `Platform` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:10` | Distinguishes macOS app, macOS CLI, and iOS app canary paths; callers pass the appropriate case to `defaultURL(for:)` at bootstrap — mixing cases writes to the wrong location. |
| `PreferencesStore` | extension | `Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift:3` | Adds `crashPromptsDefault` (= `true`) to `PreferencesStore.Prefs`; callers may rely on crash prompts being opt-out, not opt-in, per design Section 8. |
| `RecordError` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:18` | Error cases thrown by `record` for disallowed content (UUID, email, path) or empty input; callers may treat all cases as no-ops — none indicates data loss. |
| `RecordingTransport` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:14` | Test-only actor transport; accumulates sent reports in `captured` for assertion — safe to await from any isolation domain. |
| `SubmitDecision` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:10` | User's choice from the post-crash sheet; `.dontSend` short-circuits `submit(...)` before any log or breadcrumb collection — no data is gathered if the user declines. |
| `defaultURL` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:29` | Returns the platform-standard canary URL; iOS falls back to `temporaryDirectory` when the app-group container is unavailable — detection across launches may be unreliable in that case. |
| `deleteOnCleanExit` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:84` | Removes the canary file if it exists; silently no-ops when absent — safe to call unconditionally at every clean-exit lifecycle hook. |
| `detectAndPrepare` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:84` | Returns a prior-crash `CrashCanary` if the previous run did not exit cleanly, then arms a fresh canary; returns nil for same-launch pre-arms (PID match within 30-second recency window). |
| `fetchRecentLines` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:8` | Async throwing protocol requirement; conformers return rendered log lines (no metadata) since `since` for the given `subsystem`. |
| `fetchRecentLines` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:18` | Queries `OSLogStore` for entries after `position(date: since)`, filters to `subsystem`, and returns ISO-8601-prefixed composed messages; throws on store access failure. |
| `make` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:46` | Local factory inside the `passes` initializer closure; compiles a regex pattern + replacement string into a `Pass`; any invalid pattern crashes at first program load via `try!`. |
| `markCleanExit` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:66` | Deletes the canary file; call unconditionally at every clean-exit lifecycle hook — failure means the next launch falsely detects a crash. |
| `readIfPresent` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:70` | Returns the decoded `CrashCanary` or nil for a missing file; silently removes corrupt files so a bad write never permanently blocks future crash detection. |
| `record` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:27` | Appends a timestamped action to the ring buffer or throws `RecordError` if the string contains a UUID, email, path, or is empty; oldest entries are silently dropped when capacity is exceeded. |
| `redact` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:23` | Applies the fixed pipeline of regex passes to `raw` and returns the redacted result; side-effect-free and safe to call from any isolation domain. |
| `renderedAsPlainText` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift:38` | Returns a deterministic plain-text rendering suitable for a mailto body or `.lillistcrash` file; nil sections are omitted; output is stable across runs. |
| `send` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:10` | Async throwing protocol requirement; conformers deliver the report through a user-mediated channel — callers invoke only via `CrashReporter.submit(decision:...)` which guards on `.dontSend`. |
| `send` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:17` | Actor-isolated test implementation that appends the report to `captured`; callers inspect `captured` after `submit(...)` to assert report contents without I/O. |
| `send` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:30` | Encodes the report as pretty-printed ISO-8601 JSON and writes it atomically to `destination`; throws on encoding or write failure — callers surface the error to the UI. |
| `snapshot` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:49` | Returns all current entries in insertion order as an independent value-type array; callers may iterate freely without holding the actor. |
| `start` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:55` | Writes a fresh canary encoding the current PID, start time, build version, and hostname; call at every launch entry point — must precede `detectAndPrepare` to arm the current run. |
| `submit` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:100` | When `decision == .send`, fetches logs (if `includeLogs`), snapshots breadcrumbs (if `includeBreadcrumbs`), redacts via `LogRedactor`, and calls `transport.send`; completely no-ops on `.dontSend`. |
| `writeFresh` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:53` | Atomically writes the canary JSON, creating parent directories if needed; replaces any prior canary — callers must call this before `detectAndPrepare` to arm the current run. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Pass` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:36` | The entire redaction pipeline is encoded as an ordered array of `Pass` values; the struct pairs a compiled `NSRegularExpression` with its replacement template. Order is critical: wrapped-marker passes must precede key=value passes, and UUID pass must be last (iOS container paths contain UUIDs that should be elided as paths). Reordering or removing entries breaks the PII guarantee the adversarial golden fixture enforces. |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CrashReporting.fetchRecentLines -> Packages-LillistCore-Sources-LillistCore-Ordering.position (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.record -> Packages-LillistCore-Sources-LillistCore-LinkPreview.firstMatch (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.renderedAsPlainText -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`

## Type notes

`CrashReporter` is a `public actor`; all lifecycle methods are actor-isolated and must be `await`ed from async contexts. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:7`)

`BreadcrumbBuffer` is a `public actor`; `snapshot()` returns a value-type copy so callers own the array without retaining the actor after the await. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:10`)

`CanaryFile` is a synchronous `Sendable` struct — all file I/O is blocking throws, not async. Callers on actors must tolerate the blocking call or dispatch off-actor. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:7`)

`CrashReporter` accepts a `now: @Sendable () -> Date` clock injection used by `detectAndPrepare` for the recycled-PID recency check; production callers pass `{ Date() }`. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:23`)

`LogRedactor.passes` is a `private static let` initialized once at first access via `try!`; a malformed regex pattern crashes at that first load, not at `redact(_:)` call time. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:45`)

`RecordingTransport` is an actor (test-only); `FileSaveTransport` is a struct (production). Both conform to `CrashReportTransport: Sendable`. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:14`)

## External deps

- Foundation — imported
- OSLog — imported

## Gotchas

PII must be wrapped in XML-style markers (`<title>…</title>` etc.), not left bare. The defense-in-depth `key=value` passes stop at the first whitespace, so multi-word bare values like `title=Buy milk` survive redaction. Any code that logs user content must use the marker forms or the adversarial golden fixture will catch it. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:11`)

PID alone cannot distinguish a recycled-PID prior crash from a same-launch pre-arm: `detectAndPrepare` uses a 30-second `selfWriteWindow` on `startedAt` to tell them apart. A real crash with the same PID as the current process but an older `startedAt` is correctly surfaced; a same-launch pre-arm (e.g., iOS foreground-transition observer arming before `detectAndPrepare` runs) is correctly suppressed. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:25`)

On iOS, `CanaryFile.defaultURL(for: .iOSApp)` falls back to `temporaryDirectory` if the app-group container is unavailable (e.g., extension running before the main app has registered the group). The canary may be undetectable across launches in that degenerate case. (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:36`)
