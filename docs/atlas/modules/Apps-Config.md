---
module: Apps/Config
summary: "Shared xcconfig scaffold keeping the signing team ID out of git and tracking the iOS build counter"
read_when: "Code signing & build number"
sources:
  - path: Apps/Config/BuildNumber.xcconfig
    blob: 9de55af1f2dce8d8cfff66e1bb83858ab0486d3f
  - path: Apps/Config/Signing.xcconfig
    blob: 91c22af2ba9d10704a892e78b54461d6bc12d1cf
  - path: Apps/Config/Signing.local.xcconfig.example
    blob: 2c771256d16c8c8d3f09dcba171065b72979afe2
references_modules: [Apps-misc, Apps-Lillist-iOS-misc, Tools]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Apps/Config

## Purpose

Build-configuration scaffold shared by both app targets. Its central design idea
is an `$()`-indirection that keeps the Apple Developer Team ID out of every
committed file: a gitignored `Signing.local.xcconfig` supplies the real team ID,
while the committed `Signing.xcconfig` references only the placeholder. It also
holds the single source of truth for the monotonic iOS build counter. Without
this layer, either the team ID would leak into the tracked pbxproj or the build
number would lose its cross-machine continuity.

## Public API

xcconfig files expose build settings, not code symbols. The externally-consumed
settings are:

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CURRENT_PROJECT_VERSION` | build-setting | `Apps/Config/BuildNumber.xcconfig:5` | iOS build number; xcconfig precedence overrides project.yml settings.base |
| `DEVELOPMENT_TEAM` | build-setting | `Apps/Config/Signing.xcconfig:19` | Code-signing team, resolved from `$(LOCAL_DEVELOPMENT_TEAM)` at build time |
| `LOCAL_DEVELOPMENT_TEAM` | build-setting | `Apps/Config/Signing.local.xcconfig.example:13` | Local-only 10-char team ID; the gitignored override fills this in |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `#include? "Signing.local.xcconfig"` | xcconfig-include | `Apps/Config/Signing.xcconfig:13` | Optional include lets the team ID stay gitignored without breaking builds |
| `#include "BuildNumber.xcconfig"` | xcconfig-include | `Apps/Config/Signing.xcconfig:17` | Folds the tracked build counter into the signing config both targets load |

## Relationships

- `Apps-misc.project.yml -> Apps-Config.Signing.xcconfig (reads)`
- `Apps-Lillist-iOS-misc.project.yml -> Apps-Config.Signing.xcconfig (reads)`
- `Apps-Config.Signing.xcconfig -> Apps-Config.BuildNumber.xcconfig (reads)`
- `Tools.bump-build-number.sh -> Apps-Config.BuildNumber.xcconfig (writes)`

## Type notes

`Signing.xcconfig` is the entry point both app projects load via `configFiles`
for Debug and Release (`Apps/project.yml:14`, `Apps/Lillist-iOS/project.yml:14`).
It chains two includes: the optional `Signing.local.xcconfig` (absent in a fresh
checkout) and the mandatory `BuildNumber.xcconfig`. The `$(LOCAL_DEVELOPMENT_TEAM)`
indirection is literal to xcodegen — only the placeholder string lands in the
generated pbxproj — and is expanded by Xcode at build time
(`Apps/Config/Signing.xcconfig:3`). `BuildNumber.xcconfig` is tracked in git and
mutated only by the deploy script's Archive pre-action; committing after each
archive keeps the counter monotonic (`Apps/Config/BuildNumber.xcconfig:1`).
`Signing.local.xcconfig.example` is a copy-and-fill template, never consumed by a
build (`Apps/Config/Signing.local.xcconfig.example:4`).

## External deps

- xcconfig — Xcode build-configuration format; `#include` / `#include?` and `$()` variable expansion
