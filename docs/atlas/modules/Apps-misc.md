---
module: "Apps (misc)"
summary: "XcodeGen spec for the Lillist-macOS app + standalone test bundle, packages, signing, and build settings"
read_when: macOS XcodeGen project spec
sources:
  - path: Apps/project.yml
    blob: f237d599d624763bc3b7a244e3df60b9c06aaa85
references_modules: [Apps-Config, Apps-Lillist-macOS-Sources-Hotkey, Apps-Lillist-macOS-Sources-Commands, Apps-Lillist-macOS-Sources-Views-TaskList, Apps-Lillist-macOS-Sources-Views-Sidebar, Apps-Lillist-macOS-Sources-misc, Packages-LillistCore-misc, Packages-LillistUI-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps (misc)

## Purpose

XcodeGen project spec that generates `Lillist-macOS.xcodeproj` for the macOS app
and its standalone unit-test bundle. It is the single source of truth for the
macOS target graph: package dependencies, strict-concurrency/warnings-as-errors
build settings, signing indirection, and the exact set of pure helper sources
co-compiled into the test bundle so they run without a signed app test host.
Regenerating from this file is mandatory after moving or deleting macOS sources.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Lillist-macOS` | target | `Apps/project.yml:37` | macOS `application` target; product `Lillist`, bundle id `io.mikeydotio.Lillist` |
| `Lillist-macOSTests` | target | `Apps/project.yml:70` | Standalone `bundle.unit-test` (no test host) exercising co-compiled pure helpers |
| `Lillist-macOS` (scheme) | scheme | `Apps/project.yml:148` | Builds app + tests; Debug run/test config |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `configFiles` | setting | `Apps/project.yml:13` | Routes Debug+Release through `Config/Signing.xcconfig` so the team id stays out of pbxproj |
| `packages` | setting | `Apps/project.yml:27` | Declares the two local packages + remote Sparkle 2.6.0 the app links |
| `settings.base` | setting | `Apps/project.yml:17` | Swift 6, complete strict concurrency, treat-warnings-as-errors, hardened runtime |
| `TEST_HOST: ""` | setting | `Apps/project.yml:137` | Marks the test bundle host-less so headless CLI builds work without signing |

## Relationships

- `Apps-misc.Lillist-macOS -> Packages-LillistCore-misc (reads)`
- `Apps-misc.Lillist-macOS -> Packages-LillistUI-misc (reads)`
- `Apps-misc.Lillist-macOSTests -> Packages-LillistCore-misc (reads)`
- `Apps-misc.Lillist-macOSTests -> Packages-LillistUI-misc (reads)`
- `Apps-misc.configFiles -> Apps-Config (reads)`
- `Apps-misc.Lillist-macOSTests -> Apps-Lillist-macOS-Sources-Hotkey (reads)`
- `Apps-misc.Lillist-macOSTests -> Apps-Lillist-macOS-Sources-Commands (reads)`
- `Apps-misc.Lillist-macOSTests -> Apps-Lillist-macOS-Sources-Views-TaskList (reads)`
- `Apps-misc.Lillist-macOSTests -> Apps-Lillist-macOS-Sources-Views-Sidebar (reads)`
- `Apps-misc.Lillist-macOSTests -> Apps-Lillist-macOS-Sources-misc (reads)`

## Type notes

The `name:` is `Lillist-macOS` despite the directory being `Apps/` — this spec
generates the macOS-only project; the iOS app has its own spec under
`Apps/Lillist-iOS/`. The `configFiles` paths (`Config/Signing.xcconfig`,
`Apps/project.yml:14`) are relative to `Apps/`, resolving to the gitignored
`Signing.local.xcconfig` include in `Apps-Config`. The test bundle's `sources`
list each name an individual `.swift` file by repo path (e.g.
`Apps/project.yml:86`) rather than a directory, so only the pure
dependency-free helper from each app source compiles into the host-less bundle —
not the full SwiftUI/AppEnvironment graph that owns it.

## External deps

- Sparkle — remote SwiftPM package (`from: 2.6.0`) for macOS app auto-update
- AppIntents.framework — linked as an SDK only to silence `appintentsmetadataprocessor`
- XcodeGen — consumes this spec via `xcodegen generate` to produce the pbxproj

## Gotchas

- AppIntents.framework is linked but the macOS app defines no App Intents; it
  is a no-op that keeps the metadata processor quiet (`Apps/project.yml:64`).
- Test `sources` co-compile individual helper files, not directories, to avoid
  pulling in `AppEnvironment` and the full app graph (`Apps/project.yml:99`).
