# CI and Build Posture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a GitHub Actions macOS CI workflow that runs the full test/build matrix post-push on `main`, and align Lillist's build posture so every quality gate (warnings-as-errors, snapshots, pbxproj drift, the Core Data model rebuild) is enforced automatically rather than from memory.

**Architecture:** Add one `.github/workflows/ci.yml` that, on push to `main`, runs `swift test` for both SPM packages, regenerates both pbxprojs and fails on drift, runs the iOS xcodebuild test scheme (which transitively runs the app-hosted `LillistCore` host-gated tests owned by *store-swap-safety*), runs the macOS scheme tests, and does a Release-configuration archive smoke build. Separately, three source-tree posture fixes harden the same gates locally: lift `LillistUI/Package.swift` to swift-tools 6.2 with `.treatAllWarnings(as: .error)` on both source and test targets (matching `LillistCore`) while excluding the test `__Snapshots__` dirs to clear the standing manifest warning; teach the `CompileCoreDataModel` plugin to declare the inner `*.xcdatamodel/contents` and `.xccurrentversion` as `inputFiles` so model edits no longer need the manual mtime-touch ritual; and scope the brittle exact-pixel tour-snapshot precision relaxation to the single Form-bearing tour snapshot only.

**Tech Stack:** GitHub Actions (macOS runner), Swift Package Manager 6.2, `xcodebuild`, `xcodegen` 2.45, `swift-snapshot-testing`, SwiftPM build-tool plugin API (`PackagePlugin`).

**Source findings:** build-1, build-2, build-3, build-4, build-5, ui-warn-1, ui-snap-1, test-5 (roadmap item #16; closes the "No CI/CD at all" blind spot).

---

## File Structure

| Path | Create/Modify | Responsibility |
|------|---------------|----------------|
| `.github/workflows/ci.yml` | **Create** | Post-push-on-`main` macOS CI: dual `swift test`, pbxproj-drift gate, iOS + macOS xcodebuild test schemes, Release archive smoke build, failure notification on the run. |
| `Packages/LillistUI/Package.swift` | **Modify** (lines 1, 18-36) | Bump to swift-tools 6.2; add `.treatAllWarnings(as: .error)` to source + test targets; exclude test `__Snapshots__` dirs to clear the 83-file manifest warning. |
| `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` | **Modify** (lines 13-41) | Walk each `.xcdatamodeld` and declare the inner `*.xcdatamodel/contents` + `.xccurrentversion` files as `inputFiles` so editing the model auto-invalidates the `momc` command (retires the mtime-touch ritual). |
| `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` | **Modify** (lines 281-309, 558-586) | Relax snapshot precision for the one Form-bearing tour snapshot (`test_08_settings_light`) via an optional `precision`/`perceptualPrecision` param on `assertScreen`; leave all non-Form tour snapshots at exact-pixel. |
| `docs/engineering-notes.md` | **Modify** (prepend a new dated entry at line 7) | Record the CI design, the deliberate Debug-for-iteration / Release-for-CI split, the retired mtime-touch ritual, and the cross-plan dependency on store-swap-safety's app-hosted test target. |
| `CLAUDE.md` | **Modify** (the "Build-plugin caching gotcha" + "Build & test" sections) | Note CI runs post-push on `main`; mark the mtime-touch ritual as retired by the plugin fix. |

---

### Task 1: Bump LillistUI to swift-tools 6.2 with warnings-as-error and clear the manifest warning

**Files:** Modify `Packages/LillistUI/Package.swift` (whole file — current lines 1, 18-36).

This closes `ui-warn-1` (the standing "found 83 file(s) which are unhandled" manifest warning — verified live: the warning lists every `Tests/LillistUITests/**/__Snapshots__/*.png` baseline) and the LillistUI half of `build-3`/`build-4` (inconsistent warnings posture vs `LillistCore`). `LillistCore/Package.swift` is the canonical model: swift-tools `6.2`, `.treatAllWarnings(as: .error)` on source, test, executable, and CLI-test targets.

- [ ] **Step 1: Reproduce the manifest warning** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistUI 2>&1 | grep -c "unhandled"
  ```
  Expect a count `>= 1` (the warning text is `warning: 'lillistui': found 83 file(s) which are unhandled; explicitly declare them as resources or exclude from the target`). This is the failing-precondition for `ui-warn-1`.

- [ ] **Step 2: Apply the manifest edit** — replace the entire contents of `Packages/LillistUI/Package.swift` with:
  ```swift
  // swift-tools-version: 6.2
  import PackageDescription

  let package = Package(
      name: "LillistUI",
      platforms: [
          .macOS(.v15),
          .iOS(.v18)
      ],
      products: [
          .library(name: "LillistUI", targets: ["LillistUI"])
      ],
      dependencies: [
          .package(path: "../LillistCore"),
          .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0")
      ],
      targets: [
          .target(
              name: "LillistUI",
              dependencies: [
                  .product(name: "LillistCore", package: "LillistCore")
              ],
              resources: [
                  .process("Resources")
              ],
              swiftSettings: [
                  .enableExperimentalFeature("StrictConcurrency"),
                  .treatAllWarnings(as: .error)
              ]
          ),
          .testTarget(
              name: "LillistUITests",
              dependencies: [
                  "LillistUI",
                  .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
              ],
              exclude: [
                  "Recurrence/__Snapshots__",
                  "DragReorder/__Snapshots__",
                  "Tour/__Snapshots__",
                  "Snapshots/__Snapshots__",
                  "CrashReporting/__Snapshots__",
                  "iOS/__Snapshots__"
              ],
              swiftSettings: [
                  .treatAllWarnings(as: .error)
              ]
          )
      ]
  )
  ```
  Notes on the choices, all verified against the tree:
  - The six excluded paths are exactly the `__Snapshots__` directories under `Tests/LillistUITests/` (confirmed via `find Packages/LillistUI/Tests -type d -name "__Snapshots__"`: `Recurrence`, `DragReorder`, `Tour`, `Snapshots`, `CrashReporting`, `iOS`). Paths in `exclude:` are relative to the test target's source root (`Tests/LillistUITests/`). `swift-snapshot-testing` reads/writes these PNGs from disk at runtime by path, not from the resource bundle, so excluding them from the build is correct — they are test fixtures, never bundled resources.
  - `.treatAllWarnings(as: .error)` is added to **both** the source and test targets (the test target currently has no `swiftSettings:` at all), matching `LillistCore`'s posture exactly.
  - `StrictConcurrency` is kept on the source target only (matching `LillistCore`, whose test targets do not enable it — CLAUDE.md: "tests are not strict").

- [ ] **Step 3: Verify the warning is gone and the build is clean** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift build --package-path Packages/LillistUI 2>&1 | grep -c "unhandled"
  ```
  Expect `0`. Then run the host-platform test suite to prove `.treatAllWarnings(as: .error)` did not surface a latent warning-as-error in the source or test target:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistUI 2>&1 | tail -5
  ```
  Expect the suite to compile and the host-platform tests to pass (the `#if os(iOS)` snapshot/tour tests compile out on macOS — only host tests run here; that is expected). If the build now fails with a `warning treated as error`, fix the underlying warning at the source — do **not** soften the setting (house rule: warnings-as-errors, fix at the architecture level).

- [ ] **Step 4: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistUI/Package.swift && git commit -m "build(ui): swift-tools 6.2 + warnings-as-error, exclude snapshot dirs

Lift LillistUI to swift-tools 6.2 and add .treatAllWarnings(as: .error)
to the source and test targets, matching LillistCore's posture. Exclude
the six test __Snapshots__ directories so the standing 83-file manifest
warning ('found N file(s) which are unhandled') is gone — the PNG
baselines are read/written by swift-snapshot-testing at runtime by path,
never bundled.

Closes ui-warn-1; aligns build-3/build-4 warnings posture."
  ```

---

### Task 2: Declare the inner Core Data model files as plugin inputs

**Files:** Modify `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` (current lines 13-41).

This closes `build-5` and retires the manual mtime-touch ritual documented in CLAUDE.md ("Build-plugin caching gotcha") and `engineering-notes.md`. The current plugin declares `inputFiles: [inputURL]` where `inputURL` is the `.xcdatamodeld` **directory** — SwiftPM/llbuild keys the `momc` command on that directory's mtime, not on the inner `LillistModel.xcdatamodel/contents` file, so editing `contents` does not re-run `momc` and the stale `.momd` is reused (runtime `NSInvalidArgumentException: must have a valid NSEntityDescription`). The fix: keep the `.xcdatamodeld` directory as the `momc` **argument** (momc needs the bundle, not the inner file), but `FileManager`-walk it and add every inner `*.xcdatamodel/contents` plus the `.xccurrentversion` to `inputFiles` so llbuild invalidates the command on a real model edit.

- [ ] **Step 1: Confirm the current input declaration is the directory only** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "inputFiles" Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift
  ```
  Expect a single line `inputFiles: [inputURL],` where `inputURL = file.url` and `file.url.pathExtension == "xcdatamodeld"` (the directory). This is the failing-precondition for `build-5`.

- [ ] **Step 2: Apply the plugin edit** — replace the entire contents of `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift` with:
  ```swift
  import Foundation
  import PackagePlugin

  /// Build tool plugin that compiles `.xcdatamodeld` files to `.momd` using
  /// Xcode's `momc` model compiler. SwiftPM does not invoke `momc` automatically
  /// on Core Data resources, so this plugin closes the gap.
  ///
  /// Each `.xcdatamodeld` resource declared on the target is compiled and
  /// the resulting `.momd` directory ends up in the target's resource bundle,
  /// loadable via `Bundle.module.url(forResource: "<name>", withExtension: "momd")`.
  @main
  struct CompileCoreDataModel: BuildToolPlugin {
      func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
          guard let sourceTarget = target as? SourceModuleTarget else { return [] }

          let modelDirs = sourceTarget.sourceFiles.filter { file in
              file.url.pathExtension == "xcdatamodeld"
          }

          return modelDirs.map { file in
              let inputURL = file.url
              let name = inputURL.deletingPathExtension().lastPathComponent
              // Output filename intentionally differs from `<name>.momd` so
              // the plugin's output does NOT collide with Xcode's built-in
              // `DataModelCompile` rule when this package is consumed from a
              // workspace (Xcode auto-compiles the same .xcdatamodeld into
              // `<name>.momd` and the two copy commands both target the same
              // bundle path, raising a "Multiple commands produce…" error).
              // Loaders (PersistenceController) look for `<name>.momd`
              // first, then `<name>.spm.momd` as a fallback for builds where
              // only this plugin runs (`swift test` / `swift build`).
              let outputURL = context.pluginWorkDirectoryURL.appendingPathComponent("\(name).spm.momd")

              // llbuild keys a build command on the mtime of its declared
              // `inputFiles`. The `.xcdatamodeld` is a *directory*, and its
              // mtime does NOT change when the inner `*.xcdatamodel/contents`
              // file is edited — so declaring only the directory caused a
              // stale `.momd` to be reused after a model edit (runtime
              // `NSInvalidArgumentException: must have a valid
              // NSEntityDescription`). Declare the inner version files
              // (`*.xcdatamodel/contents`) and the `.xccurrentversion`
              // pointer as inputs so a real model edit invalidates `momc`.
              // momc itself still takes the `.xcdatamodeld` directory as its
              // argument — it needs the whole versioned bundle, not one file.
              let modelInputs = Self.modelInputFiles(in: inputURL)

              return .buildCommand(
                  displayName: "Compiling Core Data model \(name)",
                  executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                  arguments: ["momc", inputURL.path, outputURL.path],
                  inputFiles: [inputURL] + modelInputs,
                  outputFiles: [outputURL]
              )
          }
      }

      /// Enumerates the build-relevant files *inside* an `.xcdatamodeld`
      /// bundle that should invalidate the `momc` command when edited:
      /// every `*.xcdatamodel/contents` (one per model version) and the
      /// top-level `.xccurrentversion` pointer (present in versioned models).
      /// Returns an empty array on any enumeration failure so the build
      /// degrades to the previous directory-only behaviour rather than
      /// crashing the plugin.
      private static func modelInputFiles(in modelBundle: URL) -> [URL] {
          let fileManager = FileManager.default
          guard let enumerator = fileManager.enumerator(
              at: modelBundle,
              includingPropertiesForKeys: nil,
              options: [.skipsHiddenFiles]
          ) else {
              return []
          }

          var inputs: [URL] = []
          for case let url as URL in enumerator {
              let lastComponent = url.lastPathComponent
              let isModelContents =
                  lastComponent == "contents"
                  && url.deletingLastPathComponent().pathExtension == "xcdatamodel"
              let isCurrentVersionPointer = lastComponent == ".xccurrentversion"
              if isModelContents || isCurrentVersionPointer {
                  inputs.append(url)
              }
          }
          return inputs
      }
  }
  ```
  Note: `.skipsHiddenFiles` skips dotfiles *during traversal* but the enumerator still yields the top-level `.xccurrentversion` because it is a direct child being enumerated; to be safe the option is paired with an explicit name check. If `.xccurrentversion` is ever filtered by the hidden-files option on a future SDK, the `contents` inputs alone still close `build-5` — the version pointer only matters when you add/switch model versions, which is rare; the `contents` edit is the daily case.

- [ ] **Step 3: Prove the fix re-runs `momc` after a model edit *without* the mtime touch** — this is the regression that `build-5` is about. Run a clean build, then make a no-op-but-mtime-changing edit to `contents` and rebuild, asserting the recompile fires:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    swift build --package-path Packages/LillistCore 2>&1 | tail -2 && \
    touch -m -t 203001010000 Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents && \
    swift build --package-path Packages/LillistCore -v 2>&1 | grep -c "momc"
  ```
  Expect the second command's `grep -c "momc"` to be `>= 1` — the `momc` command re-ran because `contents` (now a declared input) changed mtime, **without** touching the `.xcdatamodeld` directory itself. Before this fix, the recompile would not fire on a `contents`-only mtime change. (Reset the mtime afterward so git doesn't see a spurious change: `touch Packages/LillistCore/Sources/LillistCore/Model/LillistModel.xcdatamodeld/LillistModel.xcdatamodel/contents` — `contents` file body is unchanged so `git status` stays clean.)

- [ ] **Step 4: Run the LillistCore suite to confirm the rebuilt model loads** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && swift test --package-path Packages/LillistCore 2>&1 | tail -5
  ```
  Expect the full suite to pass (no `NSInvalidArgumentException: must have a valid NSEntityDescription`). This proves the freshly-compiled `.spm.momd` is valid and loadable.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift && git commit -m "build(core): declare inner model files as plugin inputs

CompileCoreDataModel declared only the .xcdatamodeld *directory* as an
input, so llbuild keyed the momc command on the directory mtime — which
does not change when the inner LillistModel.xcdatamodel/contents is
edited. Stale .momd reuse then crashed at runtime with
NSInvalidArgumentException. FileManager-walk the bundle and declare each
*.xcdatamodel/contents and the .xccurrentversion as inputFiles; momc
still takes the .xcdatamodeld directory as its argument.

Retires the manual mtime-touch ritual. Closes build-5."
  ```

---

### Task 3: Scope the brittle tour-snapshot precision relaxation to the Form-bearing snapshot

**Files:** Modify `Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift` (the `test_08_settings_light` body at current lines 281-309, and the `assertScreen` helper at current lines 558-586).

This closes `ui-snap-1` (LillistUI lane: "brittle exact-pixel snapshots"). Verified live: `assertScreen` currently calls `assertSnapshot(of: host, as: .image(size: size, traits: traits), …)` with **no** `precision:`/`perceptualPrecision:` — i.e. exact-pixel (1.0). The engineering-notes entry "Snapshot test reliability: SwiftUI `Form` views drift on cold-cache runs" (2026-05-17) establishes the precedent: **`Form`-rendered snapshots** accumulate per-section AA drift and need `precision: 0.99, perceptualPrecision: 0.98`; non-Form views stay strict so they keep catching real regressions. The scope here is deliberately narrow: only `test_08_settings_light` renders a `Form` (via `SettingsScreen`, whose body is `NavigationStack { Form { … } }`, confirmed). Every other tour snapshot stays exact-pixel.

- [ ] **Step 1: Confirm `assertScreen` is exact-pixel and `test_08` is the only Form-bearing tour test** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    grep -n "as: .image" Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift && \
    grep -n "SettingsScreen\|Form" Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift
  ```
  Expect: the `assertScreen` call uses `.image(size: size, traits: traits)` (no precision); the only `SettingsScreen` reference is in `test_08_settings_light`; no other `Form` usage in the tour file. This confirms the narrow scope.

- [ ] **Step 2: Add optional precision params to `assertScreen`** — replace the `assertScreen` helper (current lines 558-586, the `private func assertScreen<V: View>( … )` through its closing `}`) with:
  ```swift
      private func assertScreen<V: View>(
          _ view: V,
          name: String,
          colorScheme: ColorScheme,
          size: CGSize,
          precision: Float = 1,
          perceptualPrecision: Float = 1,
          fileID: StaticString = #fileID,
          filePath: StaticString = #filePath,
          testName: String = #function,
          line: UInt = #line,
          column: UInt = #column
      ) {
          let host = UIHostingController(rootView:
              view.environment(\.colorScheme, colorScheme)
                  .environment(\.locale, Locale(identifier: "en_US"))
          )
          host.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
          host.view.frame = CGRect(origin: .zero, size: size)
          host.view.layoutIfNeeded()
          let traits = UITraitCollection(traitsFrom: [
              UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
              UITraitCollection(displayScale: 2)
          ])
          assertSnapshot(
              of: host,
              as: .image(precision: precision,
                         perceptualPrecision: perceptualPrecision,
                         size: size,
                         traits: traits),
              named: name,
              fileID: fileID, file: filePath, testName: testName, line: line, column: column
          )
      }
  ```
  Note: the defaults (`precision: 1, perceptualPrecision: 1`) are exact-pixel — identical to today's behaviour for every existing call site that doesn't pass them. The `Snapshotting<UIViewController, UIImage>.image(precision:perceptualPrecision:size:traits:)` factory exists in swift-snapshot-testing 1.17 (the version pinned in `Package.swift`); all four params are accepted on iOS.

- [ ] **Step 3: Apply the relaxed precision to the one Form-bearing call** — in `test_08_settings_light`, change the single assertion line (current line 308) from:
  ```swift
          assertScreen(view, name: "08-settings-light", colorScheme: .light, size: phoneSize)
  ```
  to:
  ```swift
          // SettingsScreen renders a SwiftUI Form, whose per-section AA drift
          // breaches exact-pixel on cold-cache renders (see engineering-notes
          // 2026-05-17 "Form views drift on cold-cache runs"). Relax this one
          // tour snapshot to the Form precision pair; all other tour snapshots
          // stay exact-pixel so they keep catching real regressions.
          assertScreen(view, name: "08-settings-light", colorScheme: .light,
                       size: phoneSize, precision: 0.99, perceptualPrecision: 0.98)
  ```

- [ ] **Step 4: Run the tour suite under the iOS scheme and confirm green** — these snapshots are `#if os(iOS)`, so they only run under xcodebuild, not `swift test`:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && xcodebuild test \
    -workspace Lillist.xcworkspace -scheme Lillist-iOS \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
    -only-testing:LillistUITests/IOSScreenTourTests 2>&1 | tail -15
  ```
  Expect `** TEST SUCCEEDED **` with `test_08_settings_light` passing (and all other `IOSScreenTourTests` still passing at their default exact-pixel precision). The existing `08-settings-light` baseline PNG is reused — the relaxation only widens the tolerance, it does not require re-recording.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add Packages/LillistUI/Tests/LillistUITests/Tour/IOSScreenTourTests.swift && git commit -m "test(ui): relax precision for the Form-bearing tour snapshot only

assertScreen rendered every tour snapshot at exact-pixel (1.0). The one
Form-bearing screen (test_08_settings_light, via SettingsScreen's
NavigationStack+Form) accumulates per-section AA drift on cold-cache
renders, per the 2026-05-17 engineering note. Add optional
precision/perceptualPrecision params (default 1.0 = unchanged for every
other call) and apply 0.99/0.98 to test_08 only. Non-Form tour
snapshots stay strict.

Closes ui-snap-1."
  ```

---

### Task 4: Add the GitHub Actions CI workflow

**Files:** Create `.github/workflows/ci.yml`.

This closes `build-1` (no CI), `build-2` (no pbxproj-drift gate), the CI half of `build-3`/`build-4` (warnings/Release posture enforcement), and `test-5` (the test/build matrix isn't run automatically anywhere — every gate is "what the dev remembers to run locally"). It also closes the completeness-critic blind spot "No CI/CD at all" and is the safety net that finally executes the host-gated migration tests owned by *store-swap-safety* (see the cross-plan coordination note). Triggered **post-push on `main`** because this is a solo project that commits directly to `main` (CLAUDE.md "Git workflow"): there are no PRs to gate, so CI is a post-push verifier with failure surfaced on the run.

- [ ] **Step 1: Confirm there is no existing workflow** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && ls .github/workflows 2>/dev/null || echo "NO .github/workflows"
  ```
  Expect `NO .github/workflows`. This is the failing-precondition for `build-1`.

- [ ] **Step 2: Create the workflow file** — write `.github/workflows/ci.yml` with exactly:
  ```yaml
  name: CI

  # Solo project: commits land directly on main (no PR review). CI runs
  # post-push as a verifier — it does not gate a merge, it surfaces a
  # red run + failure email if a pushed commit broke a quality gate.
  # Also runnable on demand via the Actions tab.
  on:
    push:
      branches: [main]
    workflow_dispatch:

  concurrency:
    # Newer pushes to main supersede in-flight runs for the same ref.
    group: ci-${{ github.ref }}
    cancel-in-progress: true

  jobs:
    spm:
      name: SPM packages (swift test)
      runs-on: macos-15
      timeout-minutes: 30
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Print toolchain
          run: |
            swift --version
            xcodebuild -version

        - name: Test LillistCore
          run: swift test --package-path Packages/LillistCore

        - name: Test LillistUI (host platform)
          run: swift test --package-path Packages/LillistUI

    project-drift:
      name: pbxproj drift (xcodegen)
      runs-on: macos-15
      timeout-minutes: 15
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Regenerate iOS project
          working-directory: Apps/Lillist-iOS
          run: xcodegen generate --spec project.yml --project .

        - name: Regenerate macOS project
          working-directory: Apps
          run: xcodegen generate --spec project.yml --project .

        - name: Fail on uncommitted project drift
          run: |
            if ! git diff --exit-code -- '*.xcodeproj/project.pbxproj'; then
              echo "::error::Generated pbxproj differs from the committed one."
              echo "::error::Run xcodegen locally and commit the result."
              exit 1
            fi

    ios:
      name: iOS scheme (xcodebuild test)
      runs-on: macos-15
      timeout-minutes: 45
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          # Signing.local.xcconfig is gitignored; CI builds without signing,
          # so seed the placeholder the xcconfig indirection expects. Tests
          # run on the simulator and the smoke archive uses CODE_SIGNING_ALLOWED=NO.
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Test Lillist-iOS scheme
          # Runs Lillist-iOSTests, Lillist-iOSUITests, and the
          # LillistUI/LillistUITests SPM bundle (iOS snapshot + tour tests
          # that compile out under `swift test`). When store-swap-safety
          # lands the app-hosted LillistCore host-gated tests on this scheme,
          # they execute here too — see cross-plan coordination note.
          run: |
            set -o pipefail
            xcodebuild test \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-iOS \
              -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify

    macos:
      name: macOS scheme (xcodebuild test)
      runs-on: macos-15
      timeout-minutes: 30
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Test Lillist-macOS scheme
          run: |
            set -o pipefail
            xcodebuild test \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-macOS \
              -destination 'platform=macOS' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify

    release-archive-smoke:
      name: Release archive smoke build
      runs-on: macos-15
      timeout-minutes: 45
      steps:
        - uses: actions/checkout@v4

        - name: Select Xcode 26.3
          run: sudo xcode-select -switch /Applications/Xcode_26.3.app

        - name: Install xcodegen
          run: brew install xcodegen

        - name: Generate projects
          run: |
            (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)
            (cd Apps && xcodegen generate --spec project.yml --project .)

        - name: Provide a placeholder signing team
          run: cp Apps/Config/Signing.local.xcconfig.example Apps/Config/Signing.local.xcconfig

        - name: Release-configuration build (smoke)
          # deployit archives with -configuration Debug for fast iteration
          # (Apps/Lillist-iOS/project.yml scheme: archive.config: Debug). CI
          # is the *only* place a Release-configuration compile is exercised,
          # catching Release-only optimizer/dead-code/whole-module issues that
          # Debug never sees. Smoke = compile under Release without signing;
          # not a shippable archive.
          run: |
            set -o pipefail
            xcodebuild build \
              -workspace Lillist.xcworkspace \
              -scheme Lillist-iOS \
              -configuration Release \
              -destination 'generic/platform=iOS' \
              CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
              | xcbeautify

    notify:
      name: Notify on failure
      runs-on: macos-15
      needs: [spm, project-drift, ios, macos, release-archive-smoke]
      if: failure()
      steps:
        - name: Mark the run failed
          # GitHub already emails the actor on a failed run on a branch they
          # pushed; this job makes the failure a single explicit signal at the
          # bottom of the matrix so a partial-green run reads as red at a glance.
          run: |
            echo "::error::A CI gate failed on $GITHUB_REF — see the failed job above."
            exit 1
  ```
  Design notes (all verified against the repo):
  - `macos-15` is the GitHub-hosted runner image that ships Xcode 26.x; the `xcode-select` step pins `Xcode_26.3.app` to match the local toolchain (Xcode 26.3 / Swift 6.2.4 / iOS 26.2 simulator) — the snapshot tests are simulator-version-sensitive (engineering-notes "canonical simulator pin: iPhone 17 on iOS 26.2"). If a future runner image drops 26.3, this step is the single place to bump.
  - `xcbeautify` ships preinstalled on the GitHub macOS runner images; `set -o pipefail` ensures a non-zero `xcodebuild` exit survives the pipe.
  - The drift gate uses `git diff --exit-code -- '*.xcodeproj/project.pbxproj'` so only the *generated* pbxproj is policed (not the user-data xcodegen also writes). This matches the two `xcodegen generate` invocations in CLAUDE.md.
  - The Release smoke uses `xcodebuild build -configuration Release -destination 'generic/platform=iOS'` (a device-generic compile) rather than `archive`, because `archive` would trip the build-number bump pre-action and require signing; the goal is to exercise the Release compile path, which deployit's Debug archives never do.
  - The placeholder team is copied from the committed `Apps/Config/Signing.local.xcconfig.example` (confirmed present per CLAUDE.md "Code signing"); since every CI build sets `CODE_SIGNING_ALLOWED=NO`, the actual team value is irrelevant — the file just has to exist so the `#include?` indirection resolves `$(LOCAL_DEVELOPMENT_TEAM)`.

- [ ] **Step 3: Lint the workflow YAML locally** — GitHub Actions YAML must parse; verify with the bundled Python:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ci.yml: valid YAML')"
  ```
  Expect `ci.yml: valid YAML`. If `yaml` is unavailable, fall back to `python3 -c "import json; print('skip')"` is *not* sufficient — instead use `ruby -ryaml -e "YAML.load_file('.github/workflows/ci.yml'); puts 'ok'"` (Ruby ships on macOS). Either way the YAML must load without error.

- [ ] **Step 4: Verify the local commands the workflow runs actually pass** — before relying on CI, run the two host commands the `spm` job runs (the iOS/macOS xcodebuild jobs are too slow to fully gate here, but the SPM jobs are fast and prove the matrix's foundation):
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    swift test --package-path Packages/LillistCore 2>&1 | tail -3 && \
    swift test --package-path Packages/LillistUI 2>&1 | tail -3
  ```
  Expect both suites green. Then prove the drift gate passes on the committed tree:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    (cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .) && \
    (cd Apps && xcodegen generate --spec project.yml --project .) && \
    git diff --exit-code -- '*.xcodeproj/project.pbxproj' && echo "DRIFT GATE: clean"
  ```
  Expect `DRIFT GATE: clean` (exit 0). If the regen produces a diff, the committed pbxproj is already drifted — commit the regenerated pbxproj first (that drift is pre-existing, not caused by this plan) before proceeding, so CI starts green.

- [ ] **Step 5: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add .github/workflows/ci.yml && git commit -m "ci: add post-push macOS workflow for the full test/build matrix

Solo project pushes land on main directly, so CI runs post-push as a
verifier: swift test for LillistCore + LillistUI, an xcodegen-regen +
git-diff pbxproj-drift gate, the Lillist-iOS and Lillist-macOS
xcodebuild test schemes (the iOS scheme transitively runs the
LillistUI iOS snapshot/tour bundle and, once store-swap-safety lands
it, the app-hosted host-gated LillistCore tests), and a
Release-configuration smoke build. deployit archives in Debug for
iteration; CI is the only Release-config compile.

Closes build-1, build-2, build-3, build-4, test-5; closes the
'No CI/CD at all' blind spot."
  ```

---

### Task 5: Document the CI design, the Debug/Release split, and the retired ritual

**Files:** Modify `docs/engineering-notes.md` (prepend a new dated entry directly after the header, before the first existing `## 2026-05-17` entry — i.e. insert at the blank line after line 6) and `CLAUDE.md` (the "Build-plugin caching gotcha" and "Build & test" sections).

This is the append-only engineering record (CLAUDE.md mandate) for the cross-cutting decisions made in Tasks 2 and 4 that a future contributor would otherwise rediscover the hard way: why CI is post-push, the deliberate Debug-for-deployit / Release-for-CI split, the retired mtime-touch ritual, and the dependency on *store-swap-safety*'s app-hosted test target. It also keeps the two affected CLAUDE.md sections truthful.

- [ ] **Step 1: Read the current top of engineering-notes** — confirm the insertion point:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && sed -n '1,8p' docs/engineering-notes.md
  ```
  Expect lines 1-6 to be the file header/intro and line 7 to begin `## 2026-05-17 — Plan 20a …`. The new entry is inserted as a new `##` block immediately before that line.

- [ ] **Step 2: Insert the engineering-notes entry** — using the Edit tool, insert the following block immediately before the existing `## 2026-05-17 — Plan 20a IOSScreenTourTests refactor` heading (so it becomes the newest entry at the top of the dated log):
  ```markdown
  ## 2026-05-28 — CI established + build-posture alignment (Plan: ci-and-build-posture)

  **Context.** Until now every quality gate (warnings-as-errors, the
  full test matrix, snapshots, the runtime-gated migration tests, pbxproj
  drift) was enforced only by what the dev remembered to run locally. The
  foundation review's completeness critic named "No CI/CD at all" as a
  blind spot, and `test-1`/`test-2` proved the most safety-critical tests
  already silently skip. This entry records the CI design and three
  build-posture fixes that landed with it.

  **Rules.**

  - **CI runs post-push on `main`, not as a PR gate.** This is a solo
    project that commits directly to `main` (no PR review). The workflow
    (`.github/workflows/ci.yml`) is therefore a *verifier*: a push to
    `main` triggers it, a broken gate goes red + emails the actor, and
    `workflow_dispatch` allows on-demand runs. Do not restructure it into
    a required-status-check on PRs unless the project moves to a PR flow.
  - **deployit archives in Debug for iteration; CI is the only Release
    compile.** `Apps/Lillist-iOS/project.yml`'s scheme sets
    `archive.config: Debug` deliberately — Debug archives are faster to
    produce for the ~3-5 min OTA round-trip. The cost is that
    Release-only behaviour (whole-module optimization, dead-code
    stripping, `-O` codegen differences) is never exercised by a deploy.
    CI's `release-archive-smoke` job is the *only* place a
    Release-configuration compile runs, so it is the net for Release-only
    breakage. It is a `build` (not `archive`) to avoid tripping the
    build-number bump pre-action and signing — a compile-only smoke, not
    a shippable artifact.
  - **The mtime-touch ritual for Core Data model edits is retired.** The
    `CompileCoreDataModel` plugin now declares the inner
    `*.xcdatamodel/contents` and `.xccurrentversion` files as
    `inputFiles` (it FileManager-walks the `.xcdatamodeld` bundle), so
    llbuild invalidates the `momc` command on a real model edit. Editing
    `contents` no longer requires touching both the `.xcdatamodel` and
    `.xcdatamodeld` directories. momc still receives the `.xcdatamodeld`
    directory as its argument — it needs the whole versioned bundle, not
    one file; only the *invalidation* keying changed.
  - **The pbxproj-drift gate depends on xcodegen idempotence.** CI
    regenerates both projects (`Apps/Lillist-iOS` and `Apps`) and fails
    on `git diff --exit-code` of `*.xcodeproj/project.pbxproj`. The
    `$(LOCAL_DEVELOPMENT_TEAM)` xcconfig indirection (see CLAUDE.md "Code
    signing") is what keeps regen idempotent — never put
    `DEVELOPMENT_TEAM` into `project.yml`'s `settings: base:` or the
    drift gate will flap on every contributor's team ID.
  - **Snapshot precision is relaxed only for Form-bearing snapshots.**
    The tour suite's `assertScreen` defaults to exact-pixel (1.0); only
    `test_08_settings_light` (which renders `SettingsScreen`'s
    `NavigationStack + Form`) uses `precision: 0.99, perceptualPrecision:
    0.98`, consistent with the 2026-05-17 "Form views drift on
    cold-cache runs" entry. Keep new non-Form snapshots strict.

  **Cross-plan dependency.** The `store-swap-safety` plan wires the
  `LillistCore` migration/store-swap tests into an app-hosted unit-test
  target on the `Lillist-iOS` scheme (host-gated `liveSwapAllowed`
  tests, per review findings `test-1`/`test-2`). CI's `ios` job runs
  that scheme, so once store-swap-safety lands, those previously
  silently-skipped tests execute in CI automatically — no CI change
  needed. If store-swap-safety adds a new *scheme* (rather than a target
  on the existing scheme), add a matching job here.

  **Evidence.** `.github/workflows/ci.yml` with five matrix jobs + a
  failure-notify job; `Packages/LillistUI/Package.swift` at swift-tools
  6.2 with warnings-as-error; `CompileCoreDataModel.swift` declaring
  inner-model `inputFiles`; `IOSScreenTourTests.assertScreen` precision
  params. One commit per task on `main`.
  ```

- [ ] **Step 3: Update the CLAUDE.md mtime-ritual note** — read the section first, then mark the ritual retired. Read:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "Build-plugin caching gotcha\|CompileCoreDataModel plugin keys\|Touch both directories\|touch Packages/LillistCore" CLAUDE.md
  ```
  Then, using the Edit tool on `CLAUDE.md`, prepend a one-line status note immediately under the `## Build-plugin caching gotcha` heading so the now-historical ritual is clearly marked superseded. Insert this line directly after the heading and before the existing paragraph that begins "SwiftPM's `CompileCoreDataModel` plugin keys on…":
  ```markdown
  > **Retired 2026-05-28.** The `CompileCoreDataModel` plugin now declares
  > the inner `*.xcdatamodel/contents` + `.xccurrentversion` as
  > `inputFiles`, so a model edit auto-invalidates `momc`. The touch
  > ritual below is no longer required for `swift build`/`swift test`; it
  > is kept here as historical context. See `docs/engineering-notes.md`
  > (2026-05-28 entry).
  ```

- [ ] **Step 4: Add a CI pointer to the CLAUDE.md "Build & test" section** — read the section first:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && grep -n "## Build & test\|## House rules" CLAUDE.md
  ```
  Then, using the Edit tool, insert the following note at the end of the `## Build & test` section (immediately before the `## House rules` heading that follows it):
  ```markdown
  **CI.** `.github/workflows/ci.yml` runs the full matrix post-push on
  `main` (and via `workflow_dispatch`): `swift test` for both packages, a
  pbxproj-drift gate (`xcodegen generate` + `git diff --exit-code`), the
  `Lillist-iOS` and `Lillist-macOS` xcodebuild test schemes, and a
  Release-configuration smoke build. It is a post-push verifier, not a
  merge gate (solo project, direct-to-`main`). deployit still archives in
  Debug for iteration — CI is the only Release-config compile.
  ```

- [ ] **Step 5: Verify the docs render and reference real paths** — run:
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && \
    grep -c "2026-05-28 — CI established" docs/engineering-notes.md && \
    grep -c "Retired 2026-05-28" CLAUDE.md && \
    grep -c "post-push on" CLAUDE.md
  ```
  Expect each `grep -c` to print `1` (the entries landed exactly once).

- [ ] **Step 6: Commit** —
  ```bash
  cd /Volumes/Code/mikeyward/Lillist && git add docs/engineering-notes.md CLAUDE.md && git commit -m "docs: record CI design, Debug/Release split, retired mtime ritual

Add the 2026-05-28 engineering-notes entry covering: CI is a post-push
verifier on main (not a PR gate); deployit archives in Debug for
iteration while CI's smoke job is the only Release-config compile; the
CompileCoreDataModel mtime-touch ritual is retired by the inputFiles
fix; the pbxproj-drift gate depends on xcodegen idempotence; and the
cross-plan dependency on store-swap-safety's app-hosted host-gated
tests. Mark the CLAUDE.md mtime ritual retired and add a CI pointer to
Build & test."
  ```

---

## Self-review checklist

- [ ] **build-1** (no CI / no `.github/workflows`) — closed by **Task 4** (creates `.github/workflows/ci.yml` triggered post-push on `main`).
- [ ] **build-2** (no pbxproj-drift gate) — closed by **Task 4** (`project-drift` job: `xcodegen generate` for both projects + `git diff --exit-code -- '*.xcodeproj/project.pbxproj'`).
- [ ] **build-3** (inconsistent warnings posture across packages) — closed by **Task 1** (LillistUI `.treatAllWarnings(as: .error)` on source + test, matching LillistCore) and enforced in CI by **Task 4** (`spm` job runs both `swift test`s under the strict manifests).
- [ ] **build-4** (Release/Debug posture not exercised; warnings not enforced in CI) — closed by **Task 4** (`release-archive-smoke` job is the only Release-config compile) + **Task 1** (warnings-as-error) + **Task 5** (documents the deliberate deployit-Debug / CI-Release split).
- [ ] **build-5** (`CompileCoreDataModel` keys on the `.xcdatamodeld` dir mtime, not the inner `contents`) — closed by **Task 2** (declares inner `*.xcdatamodel/contents` + `.xccurrentversion` as `inputFiles`; Step 3 proves `momc` re-runs on a `contents`-only mtime change).
- [ ] **ui-warn-1** (standing "found 83 file(s) unhandled" LillistUI manifest warning) — closed by **Task 1** (excludes the six test `__Snapshots__` dirs; Step 3 asserts the unhandled-file count drops to 0).
- [ ] **ui-snap-1** (brittle exact-pixel LillistUI snapshots) — closed by **Task 3** (scopes the `precision: 0.99, perceptualPrecision: 0.98` relaxation to the single Form-bearing tour snapshot `test_08_settings_light`; all other tour snapshots stay exact-pixel).
- [ ] **test-5** (the test/build matrix is run only from memory, never automatically) — closed by **Task 4** (CI executes `swift test` ×2, both xcodebuild schemes, the drift gate, and the Release smoke on every push to `main`; the `ios` job transitively runs the iOS snapshot/tour bundle and, via the cross-plan dependency, the app-hosted host-gated LillistCore tests).

**Strengths preserved (not refactored away):** the idempotent signing xcconfig indirection (Task 4 only *reads* the `.example` placeholder and builds with `CODE_SIGNING_ALLOWED=NO`); the canonical iPhone 17 / iOS 26.2 simulator pin and the iPhone 16 Pro logical render size (Task 4 uses the documented destination verbatim); the monotonic tracked build-number counter (Task 4's Release smoke is a `build`, not an `archive`, so it never triggers the bump pre-action); LillistCore's existing strict-concurrency + warnings-as-error posture (Task 1 mirrors it onto LillistUI rather than altering LillistCore); the snapshot suite's overall strictness (Task 3 widens tolerance for exactly one Form-bearing snapshot, leaving every other baseline strict).
