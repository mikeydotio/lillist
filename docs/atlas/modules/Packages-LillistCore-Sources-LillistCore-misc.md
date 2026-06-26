---
module: "Packages/LillistCore/Sources/LillistCore (misc)"
summary: "LillistCore cross-cutting: unified errors, device preferences, onboarding, Quick Capture handoff, logging."
read_when: "Touching LillistCore errors or device prefs"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/LillistCore.swift
    blob: f9753554726ec514cc2870e7c07ccbe049702c11
  - path: Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift
    blob: 5436856277f98ec8e3b8a8d97f0ddd79e0d44e54
  - path: Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift
    blob: a3b64fb0e7e2799357d2c23f3cad86d88192ad9a
  - path: Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift
    blob: 92ba824ecf4b96df715719c4ef2b489609411085
  - path: Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift
    blob: cdc475f7a3e5ad521318943d5dd38dfa0bf60779
  - path: Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift
    blob: 4115b679003ae244177962a72766383a654008ca
  - path: Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift
    blob: 0d1221ee7f6f5fecfc7234513383be019336858c
  - path: Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift
    blob: 636f02ff196262a60ea4580af417b32e00f4df5c
  - path: Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift
    blob: c051be3828e0433836460bd009dadbf78759bef9
  - path: Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift
    blob: 17b1c63f195499c870c6a5297d7a7cacabf759e4
references_modules: [Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistUI-Sources-LillistUI-Recurrence]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore/Sources/LillistCore (misc)

## Purpose

This module is the cross-cutting support layer of LillistCore — the infrastructure that every domain (stores, sync, CLI, extensions) depends on but that belongs to no single domain. It owns the unified error type (`LillistError`) thrown by all public APIs, the device-local preference actor (`DevicePreferencesStore`) backed by App Group `UserDefaults`, onboarding-completion state, the Quick Capture cross-process handoff mechanism, validation helpers, runtime-resolved contact info, and the `os.Logger` taxonomy. If it vanished, every other LillistCore module would lose its error contract, its preference persistence, and its logging subsystem simultaneously.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppPreferencesPartitionMigrator` | struct | `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:21` | Sendable value-type; call `runIfNeeded()` once per launch to copy pre-Plan-21 device preferences from Core Data into `DevicePreferencesStore`; fully idempotent. |
| `DefaultsInstaller` | class | `Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:32` | Init once with a `SmartFilterStore`; call `installIfNeeded()` idempotently on launch to seed the five design-specified default smart filters. |
| `DevicePreferencesStore` | actor | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:26` | Actor; App Group `UserDefaults` store for per-device preferences; all methods must be awaited; falls back to `.standard` when the App Group suite is unreachable. |
| `Issue` | struct | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:5` | Field-level validation detail nested inside `LillistError.validationFailed`; carries `field` (property name) and `message` (human-readable description); `Equatable` for test assertions. |
| `LillistCoreContact` | enum | `Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift:21` | Namespace enum; runtime-resolved crash-report recipient from Info.plist or env var; `crashReportRecipient` is resolved once at process start — use `resolveRecipient` for tests. |
| `LillistCoreInfo` | enum | `Packages/LillistCore/Sources/LillistCore/LillistCore.swift:18` | Namespace-only enum; callers read `LillistCoreInfo.version` without shadowing the `LillistCore` module name. |
| `LillistError` | enum | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:4` | Single error type thrown by all `LillistCore` public APIs; `Equatable` and `Sendable`; callers may exhaustively switch on cases without importing Foundation. |
| `LillistError` | extension | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:36` | `LocalizedError` conformance; `errorDescription` returns a non-nil human-readable string for every case — safe to display directly in alerts. |
| `LillistLog` | enum | `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift:30` | Namespace enum; central `os.Logger` factory pinned to `CrashReporting.subsystemIdentifier` — splitting subsystems silently empties the crash reporter's log-collection section. |
| `OnboardingState` | class | `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:19` | Init once with a `DevicePreferencesStore`; provides async access to the device-local onboarding-completion flag that survives Core Data store resets. |
| `Outcome` | enum | `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:48` | `.migrated` when the copy ran this invocation, `.alreadyMigrated` when the marker was set on a prior launch; equatable for test assertions. |
| `QuickCaptureHandoff` | enum | `Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift:15` | Namespace enum; cross-process mechanism for the App Intents extension to signal the main app to open Quick Capture, optionally pre-filled, via App Group `UserDefaults`. |
| `Validators` | enum | `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:4` | Internal-only validation namespace; helpers guard parent-hierarchy cycles and name uniqueness inside store methods; not exported outside `LillistCore`. |
| `crashPromptsEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:107` | Returns `true` when the key is absent (default opt-in); per-device gate controlling whether the post-crash report sheet appears. |
| `diagnosticLoggingEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:122` | Returns `DiagnosticDefaults.enabledByDefault` when absent (on in Debug, off in Release); App-Group-shared so all processes on this device see the same value. |
| `hasCompletedOnboarding` | func | `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:28` | Returns `false` on a fresh install; reads the device-local flag from App Group `UserDefaults`, not Core Data — survives a store wipe. |
| `hasCompletedOnboarding` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:54` | Returns `false` when absent (fresh install); reads key `lillist.devicePrefs.hasCompletedOnboarding` from App Group `UserDefaults`. |
| `installIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:41` | Idempotently installs the five named default smart filters; safe to call on every launch; throws on store failure. |
| `markCompleted` | func | `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:34` | Persists the onboarding-complete flag; idempotent — calling again on an already-completed flow is a no-op write. |
| `markMigrationFromCoreDataCompleted` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:184` | One-time write of the migration marker; makes `migrationFromCoreDataCompleted` return `true`, short-circuiting all future `runIfNeeded` calls. |
| `quickCaptureEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:67` | Returns `true` when absent; iOS reads as "show FAB", macOS reads as "global hotkey is active". |
| `quickCaptureHotkey` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:80` | Returns `"ctrl+opt+space"` when absent; macOS-only hotkey string; iOS reads for shape parity but never wires it. |
| `remindersImportEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:140` | Returns `false` when absent (strict opt-in); gate for the Reminders.app drain feature — must be explicitly enabled by the user. |
| `remindersImportListID` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:150` | Returns `nil` until the user picks a list; the Reminders importer is a no-op while this is `nil`. |
| `remindersInFlightIDs` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:167` | Returns the set of Reminders external identifiers already converted to tasks but not yet confirmed-deleted; guards against duplicate creation on the next drain. |
| `resetForTesting` | func | `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:39` | Resets the onboarding flag to `false`; test/debug only — not exposed in any production UI. |
| `resolveRecipient` | func | `Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift:33` | Pure, side-effect-free resolver; returns the first non-blank of its two inputs, or `""` if both are blank/nil; use this overload for unit-testable recipient resolution. |
| `runIfNeeded` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:34` | Copies device-local fields from Core Data `AppPreferences` to `DevicePreferencesStore`; short-circuits on the completion marker; `@discardableResult` when the outcome is unneeded. |
| `setCrashPromptsEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:111` | Writes `lillist.devicePrefs.crashPromptsEnabled`; controls whether the post-crash report sheet appears on next launch. |
| `setDiagnosticLoggingEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:128` | Writes `lillist.devicePrefs.diagnosticLoggingEnabled`; an explicit user choice always wins over the compile-time default. |
| `setHasCompletedOnboarding` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:57` | Writes `lillist.devicePrefs.hasCompletedOnboarding`; called by `OnboardingState.markCompleted()` and `AppPreferencesPartitionMigrator.runIfNeeded()`. |
| `setQuickCaptureEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:71` | Writes `lillist.devicePrefs.quickCaptureEnabled`; toggled by the Settings/Preferences pane; no side-effects beyond the write. |
| `setQuickCaptureHotkey` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:83` | Writes `lillist.devicePrefs.quickCaptureHotkey`; validates nothing — callers must supply a well-formed hotkey string. |
| `setRemindersImportEnabled` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:143` | Writes `lillist.devicePrefs.remindersImportEnabled`; no side-effects — callers must separately configure `remindersImportListID` before draining is useful. |
| `setRemindersImportListID` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:153` | Writes or removes `lillist.devicePrefs.remindersImportListID`; passing `nil` calls `removeObject` — no empty-string sentinel is stored. |
| `setRemindersInFlightIDs` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:170` | Writes the in-flight set as a `[String]` array; replaces the entire set — callers must merge externally if an additive update is needed. |
| `setStatusBarItemVisible` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:96` | Writes `lillist.devicePrefs.statusBarItemVisible`; macOS only — iOS ignores the value. |
| `stash` | func | `Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift:28` | Writes seed text + timestamp to App Group `UserDefaults`; an empty string still signals "open dialog"; idempotent — overwrites any prior unstale stash. |
| `statusBarItemVisible` | func | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:92` | Returns `true` when absent; macOS status-bar icon visibility gate; iOS reads for shape parity but ignores the result. |
| `take` | func | `Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift:40` | Atomically reads and clears the stash; returns `nil` if absent or older than 30s; a non-nil result (including `""`) means "open Quick Capture with this prefill". |
| `uniqueName` | func | `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:20` | Pure function; returns a non-colliding name by appending ` (2)`, ` (3)`, etc.; no I/O. |
| `wouldCreateCycle` | func | `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:8` | Walks the parent chain from `newParent` upward; returns `true` if assigning `candidate` as a descendant would create a cycle in the task hierarchy. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-misc.installIfNeeded -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.installDefaultsIfNeeded (writes)`
- `Packages-LillistCore-Sources-LillistCore-misc.quickCaptureHotkey -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc.remindersImportListID -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc.setQuickCaptureEnabled -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc.take -> Packages-LillistUI-Sources-LillistUI-Recurrence.string (calls)`

## Type notes

`DevicePreferencesStore` is an `actor` (Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:26) — all reads and writes must be awaited; its init falls back to `.standard` when the App Group suite is unreachable (line 34). `OnboardingState` and `DefaultsInstaller` are `@unchecked Sendable` final classes that hold actor/store references injected at init; they carry no mutable state themselves (Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:19, Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:32). `QuickCaptureHandoff` is a caseless namespace enum with no stored state; both `stash` and `take` open their own `UserDefaults(suiteName:)` handle per call (Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift:15). `LillistError` is `Equatable` and `Sendable` — test assertions can compare errors directly without custom matchers (Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:4). `Validators` is package-internal (lowercase `enum Validators`) despite appearing in the symbol list; it references `LillistTask` NSManagedObject directly and must stay inside LillistCore (Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:4). `AppPreferencesPartitionMigrator` is a `Sendable` struct — value semantics, no actor isolation, safe to construct per-call (Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:21).

## External deps

- CoreData — imported
- Foundation — imported
- os — imported

## Gotchas

DefaultsInstaller matches by exact filter name — a user who renames a default filter gets it re-created on next install call (Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:25-26). `quickCaptureEnabled()`, `statusBarItemVisible()`, and `crashPromptsEnabled()` default to `true` (not `false`) when the key is absent — guarded by `defaults.object(forKey:) == nil`, not a missing-key bool default (Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:68,93,107-109). `diagnosticLoggingEnabled()` delegates its absent-key default to `DiagnosticDefaults.enabledByDefault` (on in Debug, off in Release), not a hardcoded bool (Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:123-125). `QuickCaptureHandoff.take` always clears the stash even when the seed is past TTL — a stale seed is consumed and discarded, never left for the next call (Packages/LillistCore/Sources/LillistCore/QuickCaptureHandoff.swift:45-48). `AppPreferencesPartitionMigrator` intentionally leaves the legacy Core Data `AppPreferences` device-local fields in place after migration (Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:17-20). `LillistCoreContact.crashReportRecipient` is a static let resolved once at process start from Bundle.main; tests must use `resolveRecipient(_:_:)` directly (Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift:53-56). `LillistLog.subsystem` is pinned to `CrashReporting.subsystemIdentifier` — splitting it silently empties the crash reporter's log section (Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift:33).
