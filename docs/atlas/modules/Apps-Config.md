---
module: Apps/Config
summary: "xcconfig scaffolding: signing team indirection, monotonic build counter, per-machine defaults."
read_when: "Code signing & build number"
sources:
  - path: Apps/Config/BuildNumber.xcconfig
    blob: 73054a7065e4226ea920bbeefdc93d377ccb1d85
  - path: Apps/Config/Distribution.xcconfig
    blob: 84460655dcfbf0b4e127022a8ede527f6f95e614
  - path: Apps/Config/Signing.local.xcconfig.example
    blob: e1772886c706e371c5d3ac58cfe37bd6ab036193
  - path: Apps/Config/Signing.xcconfig
    blob: eaa9a2c9e55ed70c13d4f41953dc427da4dea455
generator: cartographer/4
baseline: 5882526e2241d4d941bb92533d13ae24f2d9cf17
---

# Module: Apps/Config

## Purpose

This module holds the xcconfig scaffolding that decouples build identity — signing team, build number, crash-report contact, Sparkle feed URL — from the committed pbxproj. A three-layer include cascade (public defaults in Distribution.xcconfig, optional gitignored per-machine overrides via Signing.local.xcconfig, monotonic counter in BuildNumber.xcconfig, assembled by Signing.xcconfig) keeps private and per-contributor values out of version control while still enabling fully signed local and export builds. If this module vanished, every contributor's Team ID and private infrastructure URLs would either bake into the pbxproj or signing would silently break.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

No Swift types. Four xcconfig files with defined ownership: `Signing.xcconfig` is the root compositor — it `#include`s `Distribution.xcconfig` first (public committed defaults), then `#include?`s `Signing.local.xcconfig` (gitignored per-machine file; templated by the committed `.example`), then `#include`s `BuildNumber.xcconfig` (Apps/Config/Signing.xcconfig:15–21). In xcconfig, a later assignment for the same key overrides an earlier one, so per-machine `LOCAL_*` values in the local file win over the Distribution defaults. `DEVELOPMENT_TEAM = $(LOCAL_DEVELOPMENT_TEAM)` (Apps/Config/Signing.xcconfig:23) and `LILLIST_CONTACT_EMAIL = $(LOCAL_CONTACT_EMAIL)` / `SU_FEED_URL = $(LOCAL_SU_FEED_URL)` (Apps/Config/Signing.xcconfig:28–29) are the resolved names consumed by project.yml and Info.plists. `BuildNumber.xcconfig` is the single git-tracked source of truth for `CURRENT_PROJECT_VERSION` (Apps/Config/BuildNumber.xcconfig:5), incremented by `Tools/Deploy/bump-build-number.sh` as the Lillist-iOS Archive pre-action; committing it after each archive keeps the counter monotonic across machines.

## External deps

- BuildNumber.xcconfig — imported
- Distribution.xcconfig — imported

## Gotchas

xcconfig treats `//` as a comment delimiter even mid-value, which would truncate any URL at its scheme separator. `Distribution.xcconfig` works around this with `SLASH = /` (Apps/Config/Distribution.xcconfig:23) so URL values are composed as `https:$(SLASH)$(SLASH)...` — any new URL setting must follow this pattern or the value is silently truncated. xcodegen reads the xcconfig at generation time and writes only the literal string `$(LOCAL_DEVELOPMENT_TEAM)` into `TargetAttributes.DevelopmentTeam` in the pbxproj (Apps/Config/Signing.xcconfig:8–9), not the expanded team ID — re-running `xcodegen generate` is safe and never leaks the team ID into version control.
