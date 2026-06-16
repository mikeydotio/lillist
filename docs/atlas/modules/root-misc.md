---
module: "root (misc)"
summary: "Repo-root config — CI matrix, workspace wiring, gitignore, semver state, and the canonical CLAUDE.md conventions"
read_when: "CI, workspace, repo config"
sources:
  - path: .claude/settings.local.json
    blob: f4307bbdd98b10593980431477406613e049a2f2
  - path: .github/workflows/ci.yml
    blob: 07774b20f444741c99f3e94545ccebf4a3b5d4c5
  - path: .gitignore
    blob: 4584f1163ec50f6b64de5046a96275dbd331061f
  - path: .semver/config.yaml
    blob: 1a63526d97642edb6dea7e2e800b860b1919231e
  - path: CHANGELOG.md
    blob: 67eb1a50ee5232710adb83f5af64551a3d193a74
  - path: CLAUDE.md
    blob: 7aa68e6f42c33846ce7973bc819015fc30b8ac9f
  - path: Lillist.xcworkspace/contents.xcworkspacedata
    blob: 2e734ab16d5b95d519766950140eed52205e09c8
  - path: VERSION
    blob: b043aa648f5977ee9476818a572001e989cf5348
references_modules: [Apps-Config, Tools, Packages-LillistCore-misc, Packages-LillistUI-misc, Apps-Lillist-iOS-misc, Apps-Lillist-macOS-misc]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: root (misc)

## Purpose

The repo-root control plane: the files that wire the four sub-projects into one
build, define what CI verifies, and encode the project's conventions. None ship
in an app binary, but they govern how every other module is built, tested, and
versioned. `CLAUDE.md` is the canonical narrative spec (topology, build/test
recipes, house rules); `ci.yml` is its executable counterpart; the workspace
file is the seam that joins the two packages and two apps into one buildable unit.

## Public API

(no exported code symbols — this module is configuration and documentation)

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `spm` | ci-job | `.github/workflows/ci.yml:18` | Runs `swift test` for both packages; skips host-pinned snapshot/tour suites |
| `project-drift` | ci-job | `.github/workflows/ci.yml:65` | Fails if `xcodegen generate` output differs from the committed pbxproj |
| `ios` | ci-job | `.github/workflows/ci.yml:94` | Builds all iOS scheme targets unsigned, runs only the standalone `Lillist-iOSTests` bundle |
| `macos` | ci-job | `.github/workflows/ci.yml:141` | Runs the standalone macOS test bundle unsigned |
| `release-archive-smoke` | ci-job | `.github/workflows/ci.yml:178` | Only place a Release-configuration compile is exercised |
| `localization-lint` | ci-job | `.github/workflows/ci.yml:221` | Invokes `Tools/CI/check-lillistui-localization.sh` |
| `Workspace` | xcworkspace | `Lillist.xcworkspace/contents.xcworkspacedata:2` | Joins both packages + both app projects into one buildable workspace |

## Relationships

- `root-misc.project-drift -> Apps-Lillist-iOS-misc (calls)`
- `root-misc.project-drift -> Apps-Lillist-macOS-misc (calls)`
- `root-misc.spm -> Packages-LillistCore-misc (calls)`
- `root-misc.spm -> Packages-LillistUI-misc (calls)`
- `root-misc.localization-lint -> Tools (calls)`
- `root-misc.ios -> Apps-Config (reads)`
- `root-misc.Workspace -> Packages-LillistCore-misc (owns)`
- `root-misc.Workspace -> Packages-LillistUI-misc (owns)`
- `root-misc.Workspace -> Apps-Lillist-iOS-misc (owns)`
- `root-misc.Workspace -> Apps-Lillist-macOS-misc (owns)`

## Type notes

CI is a post-push verifier, not a merge gate (solo, direct-to-`main`), declared
by the `on: push: branches: [main]` trigger at `.github/workflows/ci.yml:7`.
`notify` (`.github/workflows/ci.yml:241`) fans in from all other jobs via
`needs:` and fails loudly if any gate failed. Two test surfaces are deliberately
excluded everywhere: host-pinned snapshot/tour suites (`--skip Snapshot --skip
Tour` at `.github/workflows/ci.yml:63`) and the iCloud-dependent app-hosted /
UI tests (`-only-testing:Lillist-iOSTests` at `.github/workflows/ci.yml:137`).
The signing indirection is preserved in CI by copying
`Signing.local.xcconfig.example` to the gitignored `Signing.local.xcconfig`
(`.github/workflows/ci.yml:115`), matching the gitignore rule at
`.gitignore:137`.

`VERSION` (`VERSION:1`) and `CHANGELOG.md` (`CHANGELOG.md:6`) are managed by the
`/semver` plugin per `.semver/config.yaml:1` (`tracking`/`auto_bump` on,
`version_prefix: "v"`, `target_branch: "main"`); they must agree on the current
version string.

## External deps

- GitHub Actions — runs the CI matrix on `macos-15` runners, Xcode 26.3
- xcodegen — regenerates the two app pbxproj files; CI gates on drift
- swift / xcodebuild — package tests and app/scheme builds
- xcbeautify, jq — CI output formatting and the localization lint's JSON parsing

## Gotchas

- `LillistCore` tests run with bounded parallelism + a one-shot retry because
  concurrent in-memory containers intermittently SIGSEGV (`.github/workflows/ci.yml:49`).
- `--num-workers` requires `--parallel` on the Swift 6.2.4 toolchain; the bare
  form errors (`.github/workflows/ci.yml:48`).
- The xcworkspace `contents.xcworkspacedata` is force-tracked against the
  Xcode-Patch ignore block via `!*.xcworkspace/contents.xcworkspacedata`
  (`.gitignore:130`).
