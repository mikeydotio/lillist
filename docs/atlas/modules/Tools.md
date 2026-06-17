---
module: Tools
summary: CI localization lint and iOS archive build-number bump scripts; deployment is handled by the external deployit plugin.
read_when: Touching CI localization checks, iOS build-number bumping, or archive pre-actions
sources:
  - path: Tools/CI/check-lillistui-localization.sh
  - path: Tools/Deploy/README.md
  - path: Tools/Deploy/bump-build-number.sh
references_modules: [Apps-Config, Packages-LillistUI-misc]
generator: cartographer/1 model=claude-sonnet-4-6
---

# Module: Tools

## Purpose

Host-repo build and CI shell hooks that live outside the SwiftPM/Xcode targets
but enforce repo invariants. Two concerns: monotonic iOS build numbering (the
`Apps/Config/BuildNumber.xcconfig` counter) and a CI gate that the LillistUI
string catalog stays in sync with the strings the code actually references.
Deployment proper has moved to the external `deployit` plugin; what remains here
is the build-number bump that stays the host repo's responsibility because the
git-tracked counter is the cross-machine source of truth.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `bump-build-number.sh` | script | `Tools/Deploy/bump-build-number.sh:1` | Archive pre-action; increments `CURRENT_PROJECT_VERSION` by one, rewrites the xcconfig |
| `check-lillistui-localization.sh` | script | `Tools/CI/check-lillistui-localization.sh:1` | CI gate; exits non-zero if any extracted LillistUI string key is absent from the catalog |

## Load-bearing internals

(none — each script is a single top-level entry point with no reusable internal symbols)

## Relationships

- `Tools.bump-build-number.sh -> Apps-Config.BuildNumber.xcconfig (writes)` — script rewrites `Apps/Config/BuildNumber.xcconfig` with incremented value (`Tools/Deploy/bump-build-number.sh:25`)
- `Tools.check-lillistui-localization.sh -> Packages-LillistUI-misc.Localizable.xcstrings (reads)` — script builds `Packages/LillistUI` with `-emit-localized-strings` and diffs against `Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings` (`Tools/CI/check-lillistui-localization.sh:17`)

## Type notes

`bump-build-number.sh` is idempotent only across distinct archives, not re-runs:
each invocation reads the prior `CURRENT_PROJECT_VERSION` via `awk`, adds one, and
overwrites the file (`Tools/Deploy/bump-build-number.sh:27`–`41`), defaulting
`PREV` to 0 when the file is missing or the value is non-numeric
(`Tools/Deploy/bump-build-number.sh:31`). It resolves `REPO_ROOT` two levels up
from its own directory (`Tools/Deploy/bump-build-number.sh:22`–`23`), so it must
stay at that depth. The bumped file is git-tracked so the counter never regresses
across machines; the bump must be committed after each archive
(`Tools/Deploy/bump-build-number.sh:43`–`44`).

`check-lillistui-localization.sh` is `set -euo pipefail` and works in a `mktemp -d`
scratch dir cleaned via an `EXIT` trap (`Tools/CI/check-lillistui-localization.sh:18`–`19`).
It rebuilds LillistUI with `-emit-localized-strings`, then diffs compiler-extracted
keys against the committed catalog with `jq` + `comm` rather than `xcstringstool sync`
— the comment at `Tools/CI/check-lillistui-localization.sh:11`–`12` records that
`sync` does not merge SwiftPM-emitted `.stringsdata` on the current toolchain. The
check is one-directional: keys in source but missing from the catalog fail; extra
catalog keys are tolerated (`Tools/CI/check-lillistui-localization.sh:34`).

`Tools/Deploy/` previously held a full deploy orchestrator (`deploy-ios.sh`,
`ExportOptions.plist`, HTML/manifest templates). Those were retired when
deployment moved to the external `deployit` plugin; only `bump-build-number.sh`
survived because build-number bumping is the host repo's responsibility
(`Tools/Deploy/README.md:1`–`8`).

## External deps

- bash — both hooks; `set -euo pipefail` strictness
- jq — extracts `.tables.Localizable[].key` from `.stringsdata` and catalog keys
- swift (SwiftPM) — `swift build --package-path` with `-emit-localized-strings`
- awk / comm / sort — value extraction and key set-difference in the CI check
- deployit (external plugin) — owns iOS deploy; reads the resolved `CFBundleVersion` this bump produces (`Tools/Deploy/README.md:12`)

## Gotchas

- `check-lillistui-localization.sh` only flags keys present in source but absent from the catalog; extra keys in the catalog are silently tolerated (`Tools/CI/check-lillistui-localization.sh:34`).
- `bump-build-number.sh` falls back to `PREV=0` (producing `NEXT=1`) when `BuildNumber.xcconfig` is missing or malformed (`Tools/Deploy/bump-build-number.sh:31`).
