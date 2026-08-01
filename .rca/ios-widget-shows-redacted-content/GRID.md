# Intake Grid — ios-widget-shows-redacted-content

Both platforms' Lillist widgets render WidgetKit's placeholder content under placeholder
redaction (iOS: sample-shaped grey pills; macOS: empty grey rect) instead of real tasks, and
the widget's configuration picker is mislabeled "No Tags" and dismisses before listing
anything — a regression whose introducing build the reporter cannot name.

| Dimension | IS | IS NOT (nearest comparable) | Distinction | Recent change? |
|-----------|----|-----------------------------|-------------|----------------|
| **WHAT** — object + deviation | iOS: widget card chrome draws correctly (rainbow border, dark `workspace` background, 4 status chips, "+" affordance in the corner circle) but every `Text` is a grey redaction pill. Row structure is an exact match for `WidgetSnapshotSamples.placeholder`: 4 rows, row 2 `.started` (rendered live blue), rows 1/3/4 `.todo` outlined. macOS: empty light-grey rounded rect, no content at all. Config picker: Filter row labeled **"No Tags"**; tapping shows a spinner that immediately dismisses with nothing listed. `source: user` (screenshot + device checks), `source: inferred` high (sample-data match read off `FilterTimelineProvider.swift:15-30`) | NOT `WidgetUnavailableView` — the app's own cold-cache fallback ("Open Lillist to sync" + `arrow.triangle.2.circlepath`, `FilterWidgetEntryView.swift:77-91`) never appears. NOT a blank/crashed iOS widget — chrome renders. NOT stale or wrong data — no real content ever appears. NOT the containing apps, which work normally. `source: user` | **Sharpest.** The on-screen entry is the *placeholder* entry, so `timeline(for:in:)` delivered neither a real snapshot **nor** the `snapshot: nil` entry (which would have rendered "Open Lillist to sync"). Separately, **"No Tags" cannot be produced by any symbol in the widget target** — the widget's parameter is `@Parameter(title: "Filter")` on `SelectFilterIntent`, its entity type is `"Smart Filter"`, its sentinel title is `"No Filter"`. The repo's *only* `@Parameter(title: "Tags")` is `AddTaskIntent.tags` (`Extensions/ShortcutsActions/AddTaskIntent.swift:17`), an optional array that AppIntents renders unset as "No Tags". `source: inferred` high | See *Aligned changes* |
| **WHERE** — location | Both widget-extension processes: `app.lillist.Widget` (iOS, systemLarge observed, physical iPhone, Ad-Hoc/Production channel) and `LillistWidget-macOS` (Notification Center, Developer-ID/Production). Failure spans both the timeline path (`FilterTimelineProvider`) and the AppIntents configuration path (`SelectFilterIntent` / `SmartFilterEntityQuery`). `source: user` | NOT the iOS or macOS containing apps (both work). NOT reported for the Share extension or Shortcuts actions. Simulator behavior **unverified**. `source: user`, `source: empty` (simulator) | Fails in *both* widget processes on *both* platforms, and in *both* of the widget's Core Data-touching surfaces (cold-cache rebuild and entity query) — while the same stores are read successfully by the apps themselves. The one code path common to every failing surface is `WidgetIntentSupport.makePersistence()`. `source: inferred` med | See *Aligned changes* |
| **WHEN** — timing + pattern | Reporter: "it worked previously, but I don't remember which version broke it." Observed persistently in "the latest builds" — iOS build 92 / v0.19.0, deployed 2026-07-29 11:27 (`bb68168d`). Prior iOS deploys: build 91 / v0.18.1 (2026-07-22 10:37, `baea6688`), build 90 / v0.18.0 (2026-07-21 23:39). Steady state, not intermittent: persists across timeline refreshes and re-looks. `source: user`, `source: inferred` high (deployit serve dir + tag dates) | NOT intermittent, NOT recovered by waiting out the 30-minute backstop refresh. ~~NOT present at widget ship (2026-07-01) — `LIL-4` closed **done** 2026-07-21, a real on-device green checkpoint.~~ **CORRECTED 2026-07-30 (see `experiments/exp-1.md` §Result 3): `LIL-4` carries NO verification comment — its only comments are git bookkeeping from 2026-07-02, and its `done` state records no observed result. It is not evidence of a working widget at any date.** The last build with an SDK ≤ 26.5 is **b86, 2026-07-19**. `source: inferred` low | The failure boundary lies somewhere after 2026-07-21 (LIL-4 verified good on device) and at/before 2026-07-29 (build 92). That window contains v0.17.0 → v0.19.0 — including the entire data & sync hardening merge **and** the deploy-toolchain pin to Xcode 27. | See *Aligned changes* |
| **EXTENT** — magnitude + trend | Total functional loss of the widget feature on both platforms: zero real content rendered, and the configuration picker is unusable so the widget cannot even be pointed at a filter. Stable (not growing/shrinking). Single-user project; all of the reporter's installs affected. `source: user` | NO data loss — the underlying task data is intact and the apps read it fine. NOT a sync failure surfaced anywhere else. NOT partial (it is not "some filters work"): nothing works. `source: user` | Both the read path and the configuration path are dead, which is broader than any of the widget defects closed during the hardening program (X5/X6 were staleness and cache-blanking, not total placeholder lock). `source: inferred` med | See *Aligned changes* |

## Distinctions

Sharpest first:

1. **The picker label "No Tags" is impossible from the widget target.** `SelectFilterIntent`
   declares `@Parameter(title: "Filter", default: SmartFilterEntity.noFilter)`;
   `SmartFilterEntity.typeDisplayRepresentation` is `"Smart Filter"` and the sentinel's
   `displayRepresentation` title is `"No Filter"`. The only `"Tags"`-titled parameter anywhere
   in the repo is `AddTaskIntent.tags: [String]?` in the **ShortcutsActions** extension — an
   unset optional, which AppIntents renders as "No Tags". The configuration UI is therefore
   resolving against AppIntents metadata that does not belong to the widget's own intent.
2. **The rendered entry is the placeholder entry, not the nil-snapshot entry.** The chip
   pattern on screen (4 rows; #2 `.started` blue; #1/#3/#4 `.todo`) is byte-for-byte
   `WidgetSnapshotSamples.placeholder`. If `timeline(for:in:)` had returned normally with a
   cold cache it would have carried `snapshot: nil` and rendered `WidgetUnavailableView`
   ("Open Lillist to sync"). That view is never seen — so the timeline call is not *returning
   nil*, it is *not completing usably at all*.
3. **Every failing surface shares one dependency.** The cold-cache rebuild
   (`FilterTimelineProvider.loadSnapshot` → `WidgetIntentSupport.makePersistence()`) and the
   config picker (`SmartFilterEntityQuery` → same factory) both fail; the containing apps,
   which reach Core Data by a different route, both succeed.
4. **Cross-platform.** iOS and macOS widgets fail together despite different signing, different
   distribution channels, and (until `1c`) different store locations — which argues against an
   iOS-only packaging or provisioning explanation.
5. **Chrome renders on iOS but not macOS.** iOS gets as far as drawing the redacted card;
   macOS shows an empty rect. Same source, different failure surface — worth explaining, not
   assuming equivalent.

## Aligned changes

Everything below is a *timeline fact*, not yet a hypothesis. Boundary window:
**2026-07-21 (LIL-4 verified good on device) → 2026-07-29 (build 92, observed bad)**.

- **2026-07-29 — v0.19.0 / PR #77, the data & sync hardening program.** Widget-touching
  commits inside it:
  - `a0963538` `fix(widgets): X5 — split WidgetSnapshotBuilder.regenerate into additive vs. authoritative`
  - `7a9f90e5` + `59809ee3` `feat/fix(widgets): X6 — WidgetRefreshController observes local saves`
  - `73c2fbf8` `feat(core): suppress CloudKit mirroring for extension/widget roles (X15)`
  - `621e6ded` `fix(ios): resolve the app-group store through StoreLocation, removing the silent defaultOnDisk fallback` — a previously-silent fallback now throws
  - `56c0bcd0` `feat(core): X8 — extension processes construct a wired notification scheduler` — adds `PreferencesStore` + `NotificationScheduler` construction to the widget process
  - `0875470d` widget/history cache clearing on destructive reset
- **2026-07-20 → 07-21 — #51 agentic search, #70 compile gate, #55 Sparkle feed.** These
  bracket the LIL-4 good checkpoint on both sides.
- **Deploy toolchain pin.** `.deployit/config.toml` sets `[toolchain] min_sdk = "27"`, so
  recent builds are archived by **Xcode 27 beta**, whereas the default `xcode-select` toolchain
  is Xcode 26.6. Builds produced after that pin differ in toolchain from earlier ones —
  relevant because AppIntents metadata (`Metadata.appintents`) is generated at build time by
  the toolchain's AppIntents metadata processor.
- **`app.lillist.Widget` provisioning** (LIL-1, 2026-07-02) predates the window and is not a
  change inside it.

Verification pointers for the locate step: `git log --since=2026-07-21 --until=2026-07-30`
across `Extensions/`, `Apps/*/project.yml`, `.deployit/config.toml`, and any
`appintents`/`Metadata` build-phase or xcodegen changes.

---

Regression | known_good: none

Reporter confirms it previously worked; exact build unknown. **There is no evidenced good point on
device at any date** — the earlier claim that `LIL-4` (closed done 2026-07-21) supplied one was
wrong and is retracted (`experiments/exp-1.md` §Result 3). What the build corpus supplies instead is
a *candidate* boundary, not a verified one: the widget's build SDK crossed 26.5 → 27.0 at **b86
(2026-07-19) → b87 (2026-07-20)**, and the b86→b87 appex differential is otherwise identical
(same file set, same entitlements, only toolchain stamps + one added `libswiftCoreAudio.dylib`).

Scope correction: this grid was written when the failure was believed to be one cross-platform bug.
It is now two. The **macOS** half is diagnosed and split out as **LIL-92** (widget appex ships
without `com.apple.security.app-sandbox` because it shares the iOS entitlements file; never worked
since 2026-07-01). The **iOS** half — the originally reported defect, LIL-91 — remains open and has
no reproduction, because no runtime is available.
