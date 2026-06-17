---
module: "root (misc)"
summary: "Repo-root control plane — CI matrix, workspace wiring, gitignore, semver state, CLAUDE.md conventions, and HANDOFF.md"
read_when: "CI, workspace, repo config, or project conventions"
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
    blob: 4f9900f271c6a5908f7fcae12a878d9ae08bfe0f
  - path: CLAUDE.md
    blob: ef834043d4a074b13d2a563edae7f9d50759800b
  - path: HANDOFF.md
    blob: 1375345682e65162c93f4fbddfcec3a596d87e89
  - path: Lillist.xcworkspace/contents.xcworkspacedata
    blob: 2e734ab16d5b95d519766950140eed52205e09c8
  - path: VERSION
    blob: 60f63432822572778c3b473659da636103e7cb98
references_modules: [Apps-Config, Tools, Packages-LillistCore-misc, Packages-LillistUI-misc, Apps-Lillist-iOS-misc, Apps-Lillist-macOS-misc]
generator: cartographer/1
baseline: 34dfea7772679dbabc08fabd6fbba53f6ad5856b
---

# Module: root (misc)

## Purpose

The repo-root control plane: the files that wire the four sub-projects into one
build, define what CI verifies, and encode the project's conventions. None ship
in an app binary, but they govern how every other module is built, tested, and
versioned. `CLAUDE.md` is the canonical narrative spec (topology, build/test
recipes, house rules); `ci.yml` is its executable counterpart; the workspace
file is the seam that joins the two packages and two apps into one buildable unit.
`HANDOFF.md` carries point-in-time contributor context for active branch work.

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

`HANDOFF.md` describes point-in-time branch state for active feature work; it is
not a permanent spec. Wave completion status and any remaining manual-verification
items for a branch live there, not in CLAUDE.md. See `HANDOFF.md:139` for current
wave summary.

`.claude/settings.local.json` carries per-repo Claude Code permission grants
(e.g. `Bash(curl:*)`, `Bash(python3:*)`); it is local to the project and gitignored
by default patterns but committed here for developer consistency.

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
- `.atlas/` runtime state is gitignored at `.gitignore:144`; never commit it.
