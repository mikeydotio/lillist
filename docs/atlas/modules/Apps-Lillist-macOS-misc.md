---
module: "Apps/Lillist-macOS (misc)"
summary: "macOS app bundle entitlements, Info.plist, privacy manifest, and macOS-only localization strings"
read_when: "Touching macOS entitlements or capabilities"
sources:
  - path: Apps/Lillist-macOS/Info.plist
    blob: 7023b4c9013beb7b5bdb92d6e3d3cb31bb921139
  - path: Apps/Lillist-macOS/Lillist.entitlements
    blob: ed68765a30aa6981a6ca60ab9959954bdaf7ea20
  - path: Apps/Lillist-macOS/Resources/Localizable.xcstrings
    blob: f81ece84552c0808de5aef06b599b20cc5939e0f
  - path: Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy
    blob: 4e7e051bbe5e2753a0a80b85ae78289d250bdce7
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Apps/Lillist-macOS (misc)

## Purpose

This module holds the configuration artifacts that define the macOS app bundle's identity, capabilities, and privacy posture: entitlements, Info.plist, privacy manifest, and macOS-specific localization strings. The entitlements gate CloudKit sync to the shared `iCloud.app.lillist` container, App Group membership (`group.app.lillist`) used by the CLI and extensions, sandboxing, Reminders access, and push notification capability. Without these files the macOS app cannot be signed, cannot participate in CloudKit sync, and cannot receive text capture via the macOS Services menu entry declared in Info.plist.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All files are bundle resources with no Swift types. Entitlements are plist key-value pairs evaluated at signing time, not runtime (Apps/Lillist-macOS/Lillist.entitlements). The `com.apple.security.application-groups` value `group.app.lillist` must match the group used by the CLI's GatedPersistenceResolver and the Share/Shortcuts extensions — divergence would silently sever the shared container (Apps/Lillist-macOS/Lillist.entitlements:19-21). The Info.plist declares an NSServices entry (`addToLillistAsTask`) enabling macOS Services-menu text capture — it requires an AppDelegate handler with that selector name (Apps/Lillist-macOS/Info.plist:36-55). Sparkle auto-update keys (`SUEnableAutomaticChecks`, `SUFeedURL`, `SUPublicEDKey`) are present, making this macOS bundle the only Lillist target that integrates Sparkle for OTA updates (Apps/Lillist-macOS/Info.plist:56-61). The PrivacyInfo.xcprivacy declares UserDefaults (reason CA92.1), FileTimestamp (C617.1), and DiskSpace (85F4.1) API access — required by App Store review even though macOS distribution is via Developer-ID (Apps/Lillist-macOS/Resources/PrivacyInfo.xcprivacy:24-49).

## External deps


## Gotchas

1. macOS push entitlement key is `com.apple.developer.aps-environment` (prefixed), NOT the iOS bare `aps-environment` — using the iOS key is silently stripped by the signing pipeline (Apps/Lillist-macOS/Lillist.entitlements:5). This was a live bug before the fix. 2. The `com.apple.developer.icloud-container-environment = Development` in source is cosmetic for distribution exports: `xcodebuild -exportArchive` re-stamps both the icloud-container-environment and push entitlement from the export profile, so the source value governs only local Xcode-run builds (Apps/Lillist-macOS/Lillist.entitlements:7-8). 3. `CFBundleVersion` is hardcoded to a date string ("20260517") in Info.plist rather than drawn from an xcconfig build-number variable (Apps/Lillist-macOS/Info.plist:22) — macOS build-number bumping is manual, unlike iOS where bump-build-number.sh writes to BuildNumber.xcconfig.
