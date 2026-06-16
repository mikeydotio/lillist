---
module: "Apps/Lillist-iOS (misc)"
summary: "iOS app target manifest — xcodegen spec, bundle/entitlements/privacy plists, app-target localized strings"
read_when: iOS app target config
sources:
  - path: Apps/Lillist-iOS/Info.plist
    blob: 3fa4f9bb9a91d891e61b35325ec8f206701faf8f
  - path: Apps/Lillist-iOS/Lillist.entitlements
    blob: 45bd89c75fc209577a9f050691030a2000e74ca6
  - path: Apps/Lillist-iOS/Resources/Localizable.xcstrings
    blob: 0b929bb5c527e9ff19f4af825b212291536fd153
  - path: Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Apps/Lillist-iOS/project.yml
    blob: 93659656ee8b438360ff4ea8b20aa801dfbc0b77
references_modules: [Packages-LillistCore-misc, Packages-LillistUI-misc, Extensions-ShareExtension-iOS, Extensions-ShortcutsActions-misc, Apps-Config, Tools]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Lillist-iOS (misc)

## Purpose

The build-time spine of the iOS app: the xcodegen `project.yml` that generates the
pbxproj, plus the bundle metadata, capability entitlements, App Store privacy
manifest, and app-target localized strings. No Swift source lives here — the runtime
code is in the `Apps-Lillist-iOS-Sources-*` modules. This module decides which
targets exist, how they link the LillistCore/LillistUI packages and embed the two
extensions, how tests are hosted, and which platform capabilities (CloudKit, App
Group, push, background processing) the app declares.

## Public API

(none — this module is build configuration and resource manifests; it exports no code symbols)

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `Lillist-iOS` | xcodegen target | `Apps/Lillist-iOS/project.yml:47` | The app target; links LillistCore + LillistUI and embeds both extensions |
| `Lillist-iOSTests` | xcodegen target | `Apps/Lillist-iOS/project.yml:137` | Standalone `TEST_HOST=""` bundle — co-compiles extension sources so they unit-test without a signed host |
| `Lillist-iOSAppHostedTests` | xcodegen target | `Apps/Lillist-iOS/project.yml:211` | App-hosted bundle (real bundle ID) so `liveSwapAllowed`-gated migration/glass tests actually run |
| `configFiles` | xcodegen key | `Apps/Lillist-iOS/project.yml:13` | Wires Debug+Release to `../Config/Signing.xcconfig`, keeping the team ID out of the pbxproj |
| `BGTaskSchedulerPermittedIdentifiers` | plist key | `Apps/Lillist-iOS/Info.plist:54` | Declares `io.mikeydotio.Lillist.autopurge` background task identifier |

## Relationships

- `Apps-Lillist-iOS-misc.Lillist-iOS -> Packages-LillistCore-misc (reads)`
- `Apps-Lillist-iOS-misc.Lillist-iOS -> Packages-LillistUI-misc (reads)`
- `Apps-Lillist-iOS-misc.Lillist-iOS -> Extensions-ShareExtension-iOS (owns)`
- `Apps-Lillist-iOS-misc.Lillist-iOS -> Extensions-ShortcutsActions-misc (owns)`
- `Apps-Lillist-iOS-misc.Lillist-iOSUITests -> Apps-Lillist-iOS-misc.Lillist-iOS (reads)`
- `Apps-Lillist-iOS-misc.project.yml -> Apps-Config (reads)`
- `Apps-Lillist-iOS-misc.project.yml -> Tools (calls)`

## Type notes

The three app-extension and test targets all source files from outside this
directory via relative paths: `Lillist-iOSTests` co-compiles `SharePayload.swift`,
`ShareSaveFlow.swift`, `ReportCrashIntent.swift`, and `IntentSupport.swift` from the
`Extensions/` tree so extension logic is unit-testable in a host-free bundle
(`Apps/Lillist-iOS/project.yml:148`). `Lillist-iOSAppHostedTests` co-compiles gated
LillistCore test sources (migration, persistence, CloudKit zone erase) because they
`@testable import LillistCore` and need the app's real `CFBundleIdentifier`
(`Apps/Lillist-iOS/project.yml:223`). The Archive scheme runs a build-number bump
pre-action shelling out to `Tools/Deploy/bump-build-number.sh`
(`Apps/Lillist-iOS/project.yml:275`). All four targets share App Group
`group.io.mikeydotio.Lillist` (`Apps/Lillist-iOS/Lillist.entitlements:13`).
Bundle identity flows from build settings: `Info.plist` interpolates
`$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)` rather than hardcoding versions
(`Apps/Lillist-iOS/Info.plist:19`).

## External deps

- xcodegen — `project.yml` is its spec; `xcodegen generate` produces the pbxproj
- swift-snapshot-testing (pointfreeco) — pulled directly by `Lillist-iOSAppHostedTests` for glass snapshots
- CloudKit — declared via `com.apple.developer.icloud-services` in the entitlements
- AppIntents.framework — linked as an SDK on app + extension targets to silence the metadata processor
- BackgroundTasks — the `autopurge` task identifier and `processing` background mode

## Gotchas

- `CURRENT_PROJECT_VERSION` is deliberately kept OUT of `settings.base` so the tracked `Apps/Config/BuildNumber.xcconfig` takes effect — project pbxproj settings outrank the xcconfig (`Apps/Lillist-iOS/project.yml:25`).
- `Lillist-iOSTests` uses `TEST_HOST: ""` so headless `xcodebuild test` runs without a signing identity; the trade-off is that bundle-ID-gated live-swap tests silently skip there (`Apps/Lillist-iOS/project.yml:177`).
- `appintentsmetadataprocessor` runs on every target and warns without AppIntents linked, so even non-intent targets link `AppIntents.framework` explicitly (`Apps/Lillist-iOS/project.yml:64`).
- App-hosted snapshot fixtures are excluded from the Resources build phase (`**/__Snapshots__/**`) so recorded baselines don't churn the pbxproj (`Apps/Lillist-iOS/project.yml:221`).
