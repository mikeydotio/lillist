---
module: Tools
summary: "CI guard scripts (localization coverage, team-ID leak) and iOS archive build-number bump"
read_when: "Touching CI localization checks or build bump"
sources:
  - path: Tools/CI/check-lillistui-localization.sh
    blob: 223c47dafe800fccb53e98157d3e88c6b8af73d7
  - path: Tools/CI/check-no-team-id.sh
    blob: 8ffed8d66a9507a594b39740f66f3c0bff044212
  - path: Tools/Deploy/README.md
    blob: 1b962f2af9704077efb0d9f601076a02e4f67ee8
  - path: Tools/Deploy/bump-build-number.sh
    blob: b79272bdb5bf85d95db4b2eea071562470995dd3
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Tools

## Purpose

Tools is the local shell tooling layer: two CI guard scripts that enforce invariants the Swift compiler cannot (localization catalog coverage and signing-identity hygiene), plus the one surviving Deploy artifact after the deployit plugin migration. The CI scripts run post-push on main and act as hard gates — a missing localization key or a leaked Team ID fails the build. If this module vanished, CI would lose both correctness guards and the build-number counter would stop incrementing on archive.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

All four files are shell scripts or markdown — no Swift types, actors, or threading. check-lillistui-localization.sh builds LillistUI with `-emit-localized-strings`, collects keys from emitted .stringsdata via `jq`, and diffs against the committed Localizable.xcstrings catalog; it uses a mktemp scratch dir cleaned by a trap (Tools/CI/check-lillistui-localization.sh:18-19). check-no-team-id.sh scans only git-tracked *.pbxproj and *.xcconfig via `git grep`, matching the pattern `DEVELOPMENT_TEAM = "?[A-Z0-9]{10}` (Tools/CI/check-no-team-id.sh:27-29). bump-build-number.sh is wired as the Lillist-iOS scheme Archive pre-action; it reads the current CURRENT_PROJECT_VERSION from Apps/Config/BuildNumber.xcconfig with awk, increments it, and rewrites the whole file — Xcode 26+ fires pre-actions for both IDE and CLI xcodebuild archive invocations (Tools/Deploy/bump-build-number.sh:5-6). BuildNumber.xcconfig is git-tracked so the counter is monotonic across machines (Tools/Deploy/bump-build-number.sh:16-18).

## External deps


## Gotchas

check-lillistui-localization.sh uses `jq` key-diffing instead of `xcstringstool sync` because `sync` exits 0 and silently changes nothing when merging SwiftPM-emitted .stringsdata in the current toolchain (Tools/CI/check-lillistui-localization.sh:10-12). check-no-team-id.sh exists to guard a past regression where xcodegen/Xcode auto-mirrored the resolved DEVELOPMENT_TEAM into project.pbxproj, leaking two literal Team IDs before the repo went public (Tools/CI/check-no-team-id.sh:12-16). bump-build-number.sh runs as an Archive pre-action but Xcode resolves xcconfig settings before the pre-action executes, so the archived (shipped) build carries the PRE-bump value (PREV); the script then writes PREV+1 to BuildNumber.xcconfig, meaning the committed file always holds the next build's number — off-by-one by design (.semver/hooks/pre-bump/sync-marketing-version.sh:18-20; Tools/Deploy/bump-build-number.sh:33-41).
