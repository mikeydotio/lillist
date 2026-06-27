---
module: "Apps (misc)"
summary: "xcodegen spec generating the Lillist-macOS Xcode project (app + unit-test + UI-test targets)"
read_when: "Editing macOS target structure or scheme"
sources:
  - path: Apps/project.yml
    blob: 983aae37c65f76c863ed162b82b7d5db46d43a62
generator: cartographer/4
baseline: 8e926f08fd5269de164d25b42880893a604a9d5c
---

# Module: Apps (misc)

## Purpose

This module is the single xcodegen spec (`Apps/project.yml`) that generates the Lillist-macOS Xcode project — its three targets (app, standalone unit-test bundle, UI-test bundle), build settings, package dependencies, and scheme. Without it, `xcodegen generate` cannot produce the macOS `project.pbxproj`, so the macOS app cannot be built or tested. It is the authoritative declaration of macOS target structure, deployment target, signing indirection, and which Swift packages (LillistCore, LillistUI, Sparkle) the app links.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

Signing indirection: both Debug and Release configurations pull in `Config/Signing.xcconfig` (Apps/project.yml:13-15), which `#include?`s the gitignored `Signing.local.xcconfig` — DEVELOPMENT_TEAM never lands in the pbxproj. MARKETING_VERSION (line 30) is kept in sync with the repo `VERSION` file by the semver pre-bump hook at `.semver/hooks/pre-bump/sync-marketing-version.sh`; it must not be edited by hand. Lillist-macOSTests sets `TEST_HOST: ""` and `BUNDLE_LOADER: ""` (lines 128-129) so the unit test bundle is standalone and can build unsigned in CI; this requires co-compiling seven individual source files from the app target (lines 97-119) to give tests access to pure-value helpers (HotkeyRecorder, HotkeyKeyTable, GlobalHotkeyMonitor, CommandNotifications, EditorOpenDecision, QuickCapturePlacementMath, IndexingMappers) without importing the full app module. Lillist-macOSUITests is `CODE_SIGN_STYLE: Automatic` (line 172) and must be run on a locally signed Mac — it hosts the real Lillist-macOS app and is the only path for verifying macOS Liquid Glass, since offscreen NSHostingView capture blanks glass and there is no app-hosted snapshot path for macOS.

## External deps


## Gotchas

AppIntents.framework is linked on all three targets even though the macOS app defines no App Intents; the sole reason is to silence the `appintentsmetadataprocessor` warning that fires on every target without it (Apps/project.yml:69-74). GENERATE_INFOPLIST_FILE is set NO globally (line 25) but flipped to YES for Lillist-macOSTests (line 137) because a signed build of a test bundle requires an Info.plist even when the app supplies its own. Seven hotkey/command/editor/indexing source files are co-compiled directly into Lillist-macOSTests (lines 97-119) so their pure-value helpers are reachable from the standalone (TEST_HOST="") bundle without dragging in the full app graph. Lillist-macOSUITests requires a local signed Mac with a window server and is intentionally excluded from CI (Apps/project.yml:152-153).
