---
module: Tools
summary: "Repo-side build/CI shell hooks — iOS build-number bump and LillistUI localization-catalog check"
read_when: "CI/deploy build scripts"
sources:
  - path: Tools/CI/check-lillistui-localization.sh
    blob: 223c47dafe800fccb53e98157d3e88c6b8af73d7
  - path: Tools/Deploy/bump-build-number.sh
    blob: b79272bdb5bf85d95db4b2eea071562470995dd3
  - path: Tools/Deploy/README.md
    blob: 1b962f2af9704077efb0d9f601076a02e4f67ee8
references_modules: [Apps-Config, Packages-LillistUI-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
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

- `Tools.bump-build-number.sh -> Apps-Config.BuildNumber.xcconfig (writes)`
- `Tools.check-lillistui-localization.sh -> Packages-LillistUI-misc.Localizable.xcstrings (reads)`

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
(the comment at `Tools/CI/check-lillistui-localization.sh:11`–`12` records that
`sync` does not merge SwiftPM-emitted `.stringsdata` on the current toolchain). The
check is one-directional: keys in source but missing from the catalog fail; extra
catalog keys are tolerated (`Tools/CI/check-lillistui-localization.sh:34`).

## External deps

- bash — both hooks; `set -euo pipefail` strictness
- jq — extracts `.tables.Localizable[].key` from `.stringsdata` and catalog keys
- swift (SwiftPM) — `swift build --package-path` with `-emit-localized-strings`
- awk / comm / sort — value extraction and key set-difference in the CI check
- deployit (external plugin) — owns iOS deploy; reads the resolved `CFBundleVersion` this bump produces (`Tools/Deploy/README.md`)
