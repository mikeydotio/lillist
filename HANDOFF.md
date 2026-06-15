# HANDOFF — Rainbow Glass redesign (finish the snapshot reconciliation)

**State:** 15 commits on `main`, working tree clean, all code compiles
(both apps + both packages build). The Rainbow Glass redesign is
visually complete; the **only** remaining work is the **Wave 6 snapshot
reconciliation** — the `LillistUITests` snapshot/tour baselines are stale
(deferred batch since Wave 1), so `xcodebuild test -scheme Lillist-iOS`
and the `make test` pre-push hook are RED until this is finished. A clean
push comes after.

## What Rainbow Glass is

Evolving the Rainbow Logic design system onto Apple's iOS 26 / macOS
Tahoe **Liquid Glass**, on the Apple-idiomatic line:
- **Liquid Glass** — the *floating control layer*: FAB, toasts,
  filter-header panel, quick-capture panel, and buttons
  (`RainbowButtonStyle`).
- **Solid tinted** — *in-flow content*: status chip, task rows, toggles.
  All hand-rolled faux-3D (drop shadows, top highlights, inset wells, hue
  glows, the isometric cube) is retired.

The seam: `Packages/LillistUI/Sources/LillistUI/Theme/GlassSurface.swift`
— `glassSurface(_:in:)`, `glassGroup()`, `glassElevation()`. Roadmap +
house rules in `CLAUDE.md`; design-doc addendum at the top of
`docs/plans/2026-06-12-rainbow-logic-design-system.md`.

## THE ONE THING TO KNOW (read before touching snapshots)

Liquid Glass does not render in the standalone `LillistUITests` offscreen
snapshots — see `docs/engineering-notes.md` **2026-06-12** and the
**2026-06-14 refinement**. Proven rules:
- **Interactive glass** (`.interactive()` — the FAB; `StatusIndicatorView`'s
  Menu) blanks the *entire* offscreen capture (pure-white PNG).
- **An always-present `GlassEffectContainer`** blanks too, even if empty.
- **Non-interactive glass** (toasts, the filter panel) *does* render
  offscreen with the tour's strategy.
- Glass renders reliably only **app-hosted** (live key window, via
  `drawHierarchyInKeyWindow: true`) → `Lillist-iOSAppHostedTests/GlassSnapshotTests`.

A blank baseline is worse than none (it silently passes). Never commit
one — detect blanks by size before committing (command below).

## Done (committed)

Waves 0–5 + the content-layer flatten (Wave 3) + the status-chip revert
to a solid circle + two de-blank fixes (TasksScreen toast
`glassGroup`→`VStack`; FAB overlay removed from the tour's `phoneShell`).
`Lillist-iOSAppHostedTests/GlassSnapshotTests` (FAB, buttons, toggles,
capture-guard) is green and deterministic.

## Remaining — the reconciliation, in order

1. **Strip interactive glass from offscreen tests.** `IOSScreenTourTests
   test_06` (taskDetail) still blanks via `StatusIndicatorView`'s Menu →
   use display-only `StatusCubeView` in that mock (or move test_06
   app-hosted). Sweep for any other offscreen use of the interactive
   status control / a FAB.
2. **Migrate lone-glass iOS component tests to app-hosted, delete from
   `LillistUITests`:** the FAB + `QuickCaptureDialog` cases in
   `iOS/iOSSnapshotTests.swift`, and `iOS/QuickCaptureDialogTests.swift`.
   FAB is already covered in `GlassSnapshotTests`; add a QuickCaptureDialog
   case there.
3. **macOS app-hosted glass target (new infra).** None exists. macOS glass
   (`QuickCaptureView` panel, the inline toast, glass buttons in
   `MacOSScreenTourTests`, `Snapshots/QuickCaptureViewSnapshotTests`)
   can't be captured in `LillistUITests`. Add `Lillist-macOSAppHostedTests`
   mirroring the iOS one in `Apps/Lillist-macOS/project.yml` (TEST_HOST =
   the macOS app, + LillistUI + SnapshotTesting deps), then `xcodegen
   generate`. Move the macOS glass snapshots there. Or, if not worth the
   infra: delete those baselines and verify macOS glass manually.
4. **RECORD-rebaseline everything else** (all solid now → captures fine):
   `StatusCubeSnapshotTests` (solid circle), the Wave-3 flat cards, the
   Wave-4 flattened surfaces (sidebar/recurrence/sync/filter chip),
   `ContrastSnapshotTests`, `ReduceTransparencySnapshotTests`,
   `LocalizationSnapshotTests`, `DragReorderSnapshotTests`, the un-blanked
   tours.
5. **`ReduceTransparencySnapshotTests` may need rethinking:** on OS 26 the
   glass renderer self-handles Reduce Transparency, so the seam ignores
   the `reduceTransparencyOverride` on the glass path — those tests no
   longer exercise the opaque fallback for glass surfaces. Decide what
   they should assert now.
6. **Assert green**, then push (HTTPS, never force — see `~/.claude/CLAUDE.md`).

## Commands

```bash
# Record all iOS LillistUITests baselines (the env var maps via the scheme):
xcodebuild test -workspace Lillist.xcworkspace -scheme Lillist-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -only-testing:LillistUITests RECORD_SNAPSHOTS=YES

# App-hosted glass suite (record or assert):
#   -only-testing:Lillist-iOSAppHostedTests/GlassSnapshotTests [RECORD_SNAPSHOTS=YES]

# Detect blank (still-glassy) baselines — blanks compress tiny:
find Packages -name '*.png' -path '*__Snapshots__*' \
  -exec stat -f '%z %N' {} \; | sort -n | head -40   # inspect the smallest

# Assert (drop RECORD_SNAPSHOTS); then both packages + app builds:
swift test --package-path Packages/LillistUI
swift test --package-path Packages/LillistCore --parallel --num-workers 2
xcodebuild -workspace Lillist.xcworkspace -scheme Lillist-{iOS,macOS} <dest> build
```

After moving/adding test source files or deps, regenerate the pbxproj:
`(cd Apps/Lillist-iOS && xcodegen generate --spec project.yml --project .)`.
Glass dark-mode rendering is only trustworthy on real hardware.
