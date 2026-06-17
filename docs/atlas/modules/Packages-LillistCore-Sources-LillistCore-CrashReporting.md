---
module: Packages/LillistCore/Sources/LillistCore/CrashReporting
summary: "Canary-based crash detection plus opt-in, redacted, user-mediated crash reports"
read_when: "Touching crash detection, breadcrumb recording, log redaction, or crash report transport"
sources:
  - path: "Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift"
    blob: 1903156bfc349c5fd5ab6ea58356e7f22cf20369
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift
    blob: 74efe7dff31af290939d779fcf47d49c583a50a2
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift
    blob: 81a5e9be1a41d4a0caaeec1c3f8ac171a0d2f82f
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift
    blob: 38d7987b5923484837d05e7945c357847968768b
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift
    blob: ed24bc86615ecbc0ba4ab5b07a2830565cb72adb
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift
    blob: 0f8bd614f6f1960e4a52edb574b8c65df9ca0747
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift
    blob: adee929b22263f1fe25a2b36454e2103a21a17da
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift
    blob: 0aaab69bf29d3f1233860d00b0dc14b2a965ef7c
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift
    blob: 4c6d076cc721126adc479b806625d5a46ba8b5ce
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift
    blob: cb4793e61bc5abc2a0fe8e401a72484c3bc312fd
  - path: Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift
    blob: fdb21347e99f1aba3d1718cbfcf699687413377c
references_modules: [Apps-Lillist-iOS-Sources-App, Apps-Lillist-macOS-Sources-misc, Packages-LillistUI-Sources-LillistUI-CrashReporting, Packages-LillistCore-Sources-lillist-cli-Support, Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-Stores-chunk-2]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: Packages/LillistCore/Sources/LillistCore/CrashReporting

## Purpose

Implements design Section 8: detect a prior-run crash, then assemble an opt-in,
redacted report the user themselves delivers. A canary file written at launch
and deleted on clean exit is the detector — its survival to the next launch
means a crash. The reporting payload is composed section-by-section so nothing
identifying leaves the device unless the user keeps that toggle on, and every
transport is user-mediated (mailto / save-to-file), never a silent upload.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Breadcrumb` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/Breadcrumb.swift:8` | One ring-buffer entry: verb `action`, `at`, `success` — no PII by contract |
| `BreadcrumbBuffer` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:10` | Thread-safe last-200 action ring; rejects identifying content at `record` |
| `BreadcrumbBuffer.RecordError` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:18` | The PII-rejection contract: UUID/email/path/empty inputs throw, not log |
| `CanaryFile` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:7` | On-disk canary lifecycle: write/read/delete; resolves per-platform path |
| `CanaryFile.Platform` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:10` | Selects macOSApp / macOSCLI / iOSApp canary path; callers pass it verbatim |
| `CrashCanary` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashCanary.swift:8` | Launch identity (pid, startedAt, build, host) persisted as JSON |
| `CrashReport` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReport.swift:9` | Opt-in report bundle; `renderedAsPlainText()` is the stable text form |
| `CrashReportTransport` | protocol | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:9` | `send(_:) async throws` delivery strategy; all impls user-mediated |
| `CrashReporter` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:7` | Orchestrates detect → assemble → submit; injects canary/log/transport deps |
| `CrashReporter.SubmitDecision` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:10` | `.send` or `.dontSend`; `.dontSend` guarantees zero transport invocation |
| `CrashReporting` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift:7` | Namespace; `subsystemIdentifier` is the stable OSLog subsystem string |
| `FileSaveTransport` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:25` | Writes the report as JSON to a user-chosen `.lillistcrash` path |
| `LogFetching` | protocol | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:7` | `fetchRecentLines(since:subsystem:)`; abstracts OSLog for testability |
| `LogRedactor` | enum | `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:21` | `redact(_:)` strips PII via fixed-order idempotent regex passes |
| `OSLogFetcher` | struct | `Packages/LillistCore/Sources/LillistCore/CrashReporting/OSLogFetcher.swift:15` | Production `LogFetching` over `OSLogStore`, filtered by subsystem |
| `PreferencesStore.Prefs.crashPromptsDefault` | static var | `Packages/LillistCore/Sources/LillistCore/CrashReporting/AppPreferences+Crash.swift:7` | Default `true` — user opts out of prompts, not in |
| `RecordingTransport` | actor | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReportTransport.swift:14` | Test-only transport that captures every sent report |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `CanaryFile.defaultURL(for:)` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:29` | Per-`Platform` path resolution; app-group container for iOS, App Support for macOS |
| `CrashReporter.detectAndPrepare()` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:84` | The detection entry point; reads prior canary, re-arms, returns crash-or-nil |
| `CrashReporter.selfWriteWindow` | static let | `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:29` | 30 s recency gate that distinguishes a same-launch pre-arm from a recycled-PID crash |
| `BreadcrumbBuffer.snapshot()` | func | `Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:49` | Actor-isolated read used by `CrashReporter.submit` to capture the ring buffer at report time |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CanaryFile (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.LogFetching (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.LogRedactor (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (reads)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (calls)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.OSLogFetcher -> Packages-LillistCore-Sources-LillistCore-CrashReporting.LogFetching (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.FileSaveTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-CrashReporting.AppPreferences+Crash -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (extends)`
- `Apps-Lillist-iOS-Sources-App.CrashReporterHost -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (calls)`
- `Packages-LillistUI-Sources-LillistUI-CrashReporting.CrashReportViewModel -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Support.CLICanaryLifecycle -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporter (calls)`
- `Packages-LillistCore-Sources-lillist-cli-Commands-chunk-2.ReportCrashCommand -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReport (calls)`
- `Apps-Lillist-macOS-Sources-misc.MailtoTransport -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReportTransport (conforms-to)`
- `Packages-LillistCore-Sources-LillistCore-Stores-chunk-2.TaskStore -> Packages-LillistCore-Sources-LillistCore-CrashReporting.BreadcrumbBuffer (writes)`

## Type notes

`CrashReporter` is an actor; callers `await` every method, and it injects all
collaborators (`CanaryFile`, `LogFetching`, `BreadcrumbBuffer`, transport, plus
a `now` clock closure at `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:40`) so tests substitute fakes.
`BreadcrumbBuffer` is an actor whose entry count is capped at
`BreadcrumbBuffer.capacity` (200) inside `record` (`Packages/LillistCore/Sources/LillistCore/CrashReporting/BreadcrumbBuffer.swift:43`).
`detectAndPrepare` always re-arms via `start()` before returning, so a single
launch leaves exactly one fresh canary regardless of crash outcome. Corrupt
canary files self-delete on read (`Packages/LillistCore/Sources/LillistCore/CrashReporting/CanaryFile.swift:78`) so a poisoned write
cannot haunt later launches. All report DTOs are `Codable`/`Sendable`
value types — no Core Data escapes this module.

## External deps

- Foundation — `FileManager`, `NSRegularExpression`, JSON coding, `URL`
- OSLog — `OSLogStore`/`OSLogEntryLog` backing `OSLogFetcher`

## Gotchas

- PII redaction relies on **wrapped markers** (`<title>…</title>` etc.); the
  `key=value` passes stop at the first whitespace, so unwrapped multi-word PII
  is NOT fully redacted — see `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:14`.
- LogRedactor pass order is load-bearing: UUIDs run after paths because some iOS
  container paths embed UUIDs — see `Packages/LillistCore/Sources/LillistCore/CrashReporting/LogRedactor.swift:41`.
- PID alone cannot detect a crash (the OS recycles PIDs); the `startedAt`
  recency check is required — see `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporter.swift:76`.
- `subsystemIdentifier` must never change after release — it scopes the OSLog
  query — see `Packages/LillistCore/Sources/LillistCore/CrashReporting/CrashReporting.swift:8`.
