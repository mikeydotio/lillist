---
module: "Packages/LillistCore/Sources/LillistCore (misc)"
summary: "Cross-cutting LillistCore primitives — error type, device prefs, onboarding, logging taxonomy, validators"
read_when: "Touching LillistCore errors, device preferences, onboarding state, logging, or contact info"
sources:
  - path: Packages/LillistCore/Sources/LillistCore/LillistCore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift
  - path: Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift
  - path: Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift
  - path: Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift
  - path: Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift
  - path: Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift
  - path: Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift
  - path: Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift
references_modules: [Packages-LillistCore-Sources-LillistCore-Diagnostics, Packages-LillistCore-Sources-LillistCore-CrashReporting, Packages-LillistCore-Sources-LillistCore-Stores-chunk-1, Packages-LillistCore-Sources-LillistCore-ManagedObjects]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Packages/LillistCore/Sources/LillistCore (misc)

## Purpose

The cross-cutting primitives every other LillistCore subsystem leans on: the
single public error type, the device-local preferences store, the onboarding
gate, the unified-log taxonomy, the contact-info constant, and internal
validation helpers. These have no home in a feature folder but are depended on
package-wide — `LillistError` alone fans into nearly every store and handler.
The Plan-21 preference partition (device-local `UserDefaults` vs. CloudKit Core
Data) is the load-bearing design idea that ties the Preferences/Onboarding files
together.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AppPreferencesPartitionMigrator` | struct | `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:21` | One-time copy of pre-Plan-21 device fields out of Core Data; `runIfNeeded()` is idempotent |
| `AppPreferencesPartitionMigrator.Outcome` | enum | `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:48` | `.migrated` or `.alreadyMigrated`; return value is `@discardableResult` |
| `DefaultsInstaller` | class | `Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:32` | Idempotently installs the five default smart filters; thin wrapper over the filter store |
| `DevicePreferencesStore` | actor | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:26` | Device-local prefs in App Group `UserDefaults`; shared by app, extensions, CLI |
| `LillistCoreContact` | enum | `Packages/LillistCore/Sources/LillistCore/Support/LillistCoreContact.swift:14` | Single source of truth for user-visible contact info (`crashReportRecipient`) |
| `LillistCoreInfo` | enum | `Packages/LillistCore/Sources/LillistCore/LillistCore.swift:18` | Umbrella namespace; holds package `version` string |
| `LillistError` | enum | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:4` | The one `Error` type all public LillistCore APIs throw; `Sendable`, `Equatable`, `LocalizedError` |
| `LillistError.Issue` | struct | `Packages/LillistCore/Sources/LillistCore/Validation/LillistError.swift:5` | Field+message pair carried by `.validationFailed`; how validators report errors |
| `LillistLog` | enum | `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift:30` | `os.Logger` taxonomy; subsystem pinned to the crash reporter's so shipped logs are non-empty |
| `OnboardingState` | class | `Packages/LillistCore/Sources/LillistCore/Onboarding/OnboardingState.swift:19` | First-launch gate; reads/writes `hasCompletedOnboarding` via the device store |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Validators.wouldCreateCycle` | func | `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:8` | Guards task reparenting against cycles by walking the `parent` chain |
| `Validators.uniqueName` | func | `Packages/LillistCore/Sources/LillistCore/Validation/Validators.swift:20` | Appends ` (2)`, ` (3)` to de-collide names against an existing set |
| `DevicePreferencesStore.quickCaptureHotkeyDefault` | static let | `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:77` | Default hotkey spec (`ctrl+opt+space`) when the user hasn't customized one |
| `LillistLog.signposter` | static let | `Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift:54` | Shared `OSSignposter` for migration-runner and heavy-fetch intervals |

## Relationships

- `Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore -> Packages-LillistCore-Sources-LillistCore-Diagnostics.DiagnosticDefaults (reads)`
- `Packages-LillistCore-Sources-LillistCore-misc.LillistLog -> Packages-LillistCore-Sources-LillistCore-CrashReporting.CrashReporting (reads)`
- `Packages-LillistCore-Sources-LillistCore-misc.DefaultsInstaller -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.SmartFilterStore (calls)`
- `Packages-LillistCore-Sources-LillistCore-misc.AppPreferencesPartitionMigrator -> Packages-LillistCore-Sources-LillistCore-Stores-chunk-1.PreferencesStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-misc.AppPreferencesPartitionMigrator -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (writes)`
- `Packages-LillistCore-Sources-LillistCore-misc.OnboardingState -> Packages-LillistCore-Sources-LillistCore-misc.DevicePreferencesStore (reads)`
- `Packages-LillistCore-Sources-LillistCore-misc.Validators -> Packages-LillistCore-Sources-LillistCore-ManagedObjects.LillistTask (reads)`

## Type notes

`DevicePreferencesStore` is an `actor`; its accessors are `async`, and callers
(`OnboardingState`, `AppPreferencesPartitionMigrator`) `await` across the
isolation boundary. It is constructed from an App Group `appGroupID` and falls
back to `.standard` when the suite is unreachable (e.g. unsigned test sandbox),
seen at `Packages/LillistCore/Sources/LillistCore/Preferences/DevicePreferencesStore.swift:34`.
Boolean prefs default to `true` via an explicit `object(forKey:) == nil` check,
not `bool(forKey:)`'s implicit `false`.

`OnboardingState`, `DefaultsInstaller`, and `AppPreferencesPartitionMigrator`
own no state of their own — each holds an injected store reference and is a thin
async facade. `OnboardingState` and `DefaultsInstaller` are `@unchecked
Sendable`; the migrator is plain `Sendable`.

Idempotency invariant: `AppPreferencesPartitionMigrator.runIfNeeded()`
short-circuits once `DevicePreferencesStore.migrationFromCoreDataCompleted` is
set, at `Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:35`.

`Validators` is module-internal (no `public`), so its symbols never leave
LillistCore even though they reference managed-object types.

## External deps

- Foundation — `UserDefaults`, `URL`, `UUID`, `LocalizedError`
- os — `Logger`, `OSSignposter` for the `LillistLog` taxonomy
- CoreData — `Validators` reads `LillistTask.objectID` / `parent` for cycle checks

## Gotchas

- `LillistLog.subsystem` is deliberately pinned to `CrashReporting.subsystemIdentifier`; splitting it empties the crash report's "Recent app logs" section (`Packages/LillistCore/Sources/LillistCore/Support/LillistLog.swift:33`).
- Renaming a default smart filter makes `DefaultsInstaller` re-create a fresh copy; matching is by exact name (`Packages/LillistCore/Sources/LillistCore/Onboarding/DefaultsInstaller.swift:25`).
- Core Data `AppPreferences` device-local fields are intentionally left in the model post-migration, not removed (`Packages/LillistCore/Sources/LillistCore/Preferences/AppPreferencesPartitionMigrator.swift:16`).
