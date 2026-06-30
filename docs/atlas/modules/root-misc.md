---
module: "root (misc)"
summary: "Workspace root: CI matrix, semver hooks, deployit export options, and xcworkspace binding all four targets."
read_when: "CI, workspace, or semver bump config"
sources:
  - path: .claude/settings.local.json
    blob: f4307bbdd98b10593980431477406613e049a2f2
  - path: .deployit/ExportOptions.ios.plist
    blob: fff37ca09136c1b41eab101087997b02b4ecb3ef
  - path: .deployit/ExportOptions.macos.plist
    blob: 86b4aa121213a3e16fecd5dc235afaed57caeec2
  - path: .gitattributes
    blob: 03a22ed38fd5133362b52dcdec46c1772a2477c9
  - path: .github/workflows/ci.yml
    blob: e97cfe992413054546e553108951cc4c0b94c67e
  - path: .semver/config.yaml
    blob: 1a63526d97642edb6dea7e2e800b860b1919231e
  - path: .semver/hooks/pre-bump/sync-marketing-version.sh
    blob: eb38f15b18b0dc779e1276fd479e877017e40169
  - path: CHANGELOG.md
    blob: 328db62d635baeec0cb7da4786eced7ce19f2e14
  - path: HANDOFF.md
    blob: c507d9e2183b882c613cf819ea95bd274f96df5d
  - path: LICENSE
    blob: 38fa01bc5e183db7bc03fdf42c693199b2d37d4a
  - path: Lillist.xcworkspace/contents.xcworkspacedata
    blob: 2e734ab16d5b95d519766950140eed52205e09c8
  - path: README.md
    blob: ab008a361236b5a15520599a92ce4f8a544a7548
  - path: THIRD-PARTY-LICENSES.md
    blob: 4248c37799371a584b25acb4ffd8131cc694f694
  - path: VERSION
    blob: 1784198fa99ba3f116d786fda4228ca7f7ed218f
generator: cartographer/4
baseline: 5882526e2241d4d941bb92533d13ae24f2d9cf17
---

# Module: root (misc)

## Purpose

root-misc is the repo's integrating scaffold: the xcworkspace that binds both SPM packages and both Xcode apps into a single build graph, the CI workflow that enforces quality gates post-push, the deployit export options that pin both platforms to the Production CloudKit environment at distribution time, and the semver hook that keeps MARKETING_VERSION in lockstep with the VERSION file. Without it, there is no authoritative build-and-test matrix, no consistent CloudKit environment selection at export, and no version-number coherence across the workspace. It also carries the .gitattributes marking docs/atlas/ as linguist-generated and the .semver config governing changelog format and git tagging.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

CI is a post-push verifier (not a merge gate); newer pushes to main cancel in-flight runs via the `ci-${{ github.ref }}` concurrency group (.github/workflows/ci.yml:14-15). LillistCore tests run `--parallel --num-workers 2` with a one-shot retry to absorb Core Data SIGSEGV and wall-clock flakes; snapshot/tour tests are unconditionally excluded because baselines are host-pinned (.github/workflows/ci.yml:51-52,63). App-hosted migration tests and UI tests are excluded: they require a live NSPersistentCloudKitContainer and an iCloud-signed Mac (.github/workflows/ci.yml:119-126). The xcworkspace references both SPM packages as `group:` file refs and both Xcode projects; all four entries are required for xcodebuild workspace resolution (Lillist.xcworkspace/contents.xcworkspacedata:3-6). iOS export is `ad-hoc` (Apple Distribution-signed) targeting Production CloudKit; macOS export is `developer-id` + notarization also targeting Production; `iCloudContainerEnvironment` is set explicitly in both plists so xcodebuild -exportArchive re-stamps the binary (.deployit/ExportOptions.ios.plist:30,33; .deployit/ExportOptions.macos.plist:31,33). The semver pre-bump hook fires before the chore(release) commit; it updates MARKETING_VERSION in both project.yml specs, regenerates pbxprojs via xcodegen, and git-stages them so they land in the bump commit (.semver/hooks/pre-bump/sync-marketing-version.sh:79-88).

## External deps


## Gotchas

CI includes a `release-archive-smoke` job because deployit archives Debug; Release-only optimizer/dead-code issues are only caught here (.github/workflows/ci.yml:205-206). A `secrets-guard` job scans committed pbxproj/xcconfig for literal Apple Developer Team IDs; two leaked this way before the $(LOCAL_DEVELOPMENT_TEAM) indirection was established (.github/workflows/ci.yml:248-250). The semver pre-bump hook strips the leading 'v' before writing MARKETING_VERSION because CFBundleShortVersionString must be numeric (.semver/hooks/pre-bump/sync-marketing-version.sh:47). The hook derives project root from its own path (not CWD) and exits 1 if xcodegen is absent, since stale pbxprojs would cause a version mismatch (.semver/hooks/pre-bump/sync-marketing-version.sh:37,73-76). `--num-workers N` requires `--parallel` on this toolchain; the bare form errors, which is why CI always passes both flags (.github/workflows/ci.yml:51).
