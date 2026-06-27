---
module: "Apps/Lillist-iOS (misc)"
summary: "iOS app target config: xcodegen spec, Info.plist, entitlements, localization, and privacy manifest."
read_when: "Touching iOS app target or entitlements"
sources:
  - path: Apps/Lillist-iOS/Info.plist
    blob: 8994933e1beb6d6449bbd14073e34f94fa2e7c87
  - path: Apps/Lillist-iOS/Lillist.entitlements
    blob: c898a3df7c5036e8dc9dcdfa5fd52659bbd82107
  - path: Apps/Lillist-iOS/Resources/Localizable.xcstrings
    blob: 1bf0907c6002198ad7b3c8aaeb6bb650f86f4642
  - path: Apps/Lillist-iOS/Resources/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
  - path: Apps/Lillist-iOS/project.yml
    blob: d87ab49afa0905417a3d7230874f316f9e2d93b7
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Apps/Lillist-iOS (misc)

## Purpose

This module holds all non-Swift configuration artifacts that define the iOS app target: the xcodegen project spec (project.yml), Info.plist, entitlements, localization catalog, and App Store privacy manifest. Together they establish the app's bundle identity, capability grants (CloudKit, App Groups, push notifications, Reminders access), build-variable topology, and the full test-target harness (standalone, app-hosted, UI, and LillistUI snapshot bundles). Without these files the iOS target cannot be declared, signed, or built, and the three-way extension embed graph (ShareExtension-iOS, ShortcutsActions, AppIntents SDK) has no definition.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

`project.yml` is the xcodegen source; `Apps/Lillist-iOS/project.yml` is the authoritative build spec — `pbxproj` is a generated artifact and must be regenerated after any edit here (`xcodegen generate`). `CURRENT_PROJECT_VERSION` is intentionally absent from `project.yml` settings so `Apps/Config/BuildNumber.xcconfig` (tracked, auto-incremented by the Archive pre-action) is not outranked by a project-level setting (`Apps/Lillist-iOS/project.yml:25-28`). `MARKETING_VERSION` is kept in lockstep with the `VERSION` file via `.semver/hooks/pre-bump/sync-marketing-version.sh`; hand-editing one without the other breaks version display (`Apps/Lillist-iOS/project.yml:39`). The entitlements file declares `aps-environment = development` — this value is cosmetic for exported/distributed builds because `xcodebuild -exportArchive` re-stamps it from the export profile; only local Xcode-run (Development-signed) builds read the source value (`Apps/Lillist-iOS/Lillist.entitlements:6`). `Lillist-iOSAppHostedTests` sets `TEST_HOST` to the built Lillist.app so `Bundle.main.bundleIdentifier` resolves to the real app ID — this is the mechanism that allows `liveSwapAllowed`-gated migration/store-swap tests to execute instead of silently skipping (`Apps/Lillist-iOS/project.yml:265-266`). `Lillist-iOSTests` uses `TEST_HOST: ""` to allow headless unsigned CI runs (`Apps/Lillist-iOS/project.yml:191`).

## External deps


## Gotchas

`AppIntents.framework` is linked explicitly on all three app/extension targets to silence an `appintentsmetadataprocessor` warning that fires even when the target has no `import AppIntents`; without it the processor warns about a missing framework linkage on every build (`Apps/Lillist-iOS/project.yml:74-79`). `RECORD_SNAPSHOTS` is propagated to test processes via a scheme environment variable using `$(RECORD_SNAPSHOTS)` build-setting expansion — plain environment variables do NOT survive `xcodebuild test`, so passing `-env RECORD_SNAPSHOTS=YES` would silently do nothing (`Apps/Lillist-iOS/project.yml:307-311`). `__Snapshots__` fixture directories under `Tests/AppHostedTests/` are excluded from the Resources build phase so recorded baselines do not generate per-PNG pbxproj churn (`Apps/Lillist-iOS/project.yml:233-236`). `LillistUITests` (the SPM bundle) is wired into the Lillist-iOS scheme test targets as `package: LillistUI/LillistUITests` — this is the only way `#if os(iOS)`-guarded snapshot tests in that package actually run; the package's own `swift test` on a macOS host compiles them out (`Apps/Lillist-iOS/project.yml:300-303`).
