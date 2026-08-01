# INCONCLUSIVE — ios-widget-shows-redacted-content (LIL-91, iOS)

**No iOS root cause is named.** Every hypothesis formed was refuted, re-attributed to a different
defect, or left unverifiable without runtime. This file records what was established, what was
killed, and the exact evidence that would discriminate — so a resumption starts from facts rather
than from re-derivation.

**Scope note.** The macOS half of the original report *was* diagnosed and is **not** covered here:
see **LIL-92** (widget appex ships without `com.apple.security.app-sandbox` because it shares the
iOS entitlements file; never worked since 2026-07-01). This document is the **iOS** half only.

## Established (survives challenge)

- The widget appex is built against **SDK 27.0** from **b87 / v0.16.0 / 2026-07-20** onward;
  `minos` and `Info.plist MinimumOSVersion` are **26.0 on both app and appex in every build**.
- The widget appex is **present** in every post-feature build; nothing dropped it from packaging.
- **Provisioning, entitlements, and AppIntents metadata are clean and eliminated.**
  `embedded.mobileprovision` is content-equivalent across b86/b87/b92; b92's signed appex carries
  `com.apple.security.application-groups = ["group.app.lillist"]`, so `GatedPersistenceResolver
  .init?` cannot fail on a missing container. Widget metadata declares `SelectFilterIntent` →
  parameter `Filter`, entity `SmartFilterEntity`, correct `WidgetConfiguration` system protocol;
  zero occurrences of `Tags`.
- **No debug-dylib** in the shipped appex (b86/b87/b92) — that packaging vector is retired.
- **#51 / #70 do not reach the widget's runtime.** The widget links no new module across the
  boundary; `FoundationModels.framework` was gained by the **app** only.
- **No entry is reaching the host.** The widget renders `placeholder(in:)`'s sample under placeholder
  redaction, and `SmartFilterEntityQuery.suggestedEntities()` cannot return an empty list
  (`[.noFilter] + saved`) — so "spinner, then dismisses with nothing listed" means the query **never
  returned**: process death mid-query, or no launch.

## Killed

| # | Hypothesis | Outcome |
|---|---|---|
| **H2** | Duplicate/stale registration shadows the live record | **REFUTED** — `pluginkit -m -v -i app.lillist.Widget` → "(no matches)"; PlugInKit holds no record at all |
| **H3** | Developer-ID/notarized channel differs from Debug | **SUBSUMED** by H5 |
| **H5** | Missing `com.apple.security.app-sandbox` | **CONFIRMED but macOS-only** → split out as **LIL-92** |
| **H1** | Beta-SDK appex fails to load/register on iOS 26.x | **INSUFFICIENT, leaning REFUTED on mechanism** — see `CHALLENGE.md` |

**Why H1's mechanism fails:** loaders gate on `minos`/`MinimumOSVersion` (both correct at 26.0); the
`sdk` field is not a load gate. No documented rule refuses a bundle on build-SDK alone. Real-world
precedent for beta-SDK widget breakage exists but always manifests as **a crash at extension launch**,
never a registration refusal — supporting the *trigger* while contradicting the *mechanism*.

**Why the b87 boundary fails:** it was selected circularly (chosen because the SDK changed there, then
reported as the only change there), and **there are zero widget-source commits between 2026-07-14 and
2026-07-28** — b86 and b87 contain identical widget-specific source. Withdrawing `LIL-4` removed the
one datum that could have falsified H1; that widens the window rather than supporting it.

**The registration tail was never measured on iOS.** It was inherited from the macOS `pluginkit`
result, which now belongs to LIL-92. On iOS it is an assumption.

## Leading candidates for a resumption (both outrank H1)

1. **Extension process death — jetsam or crash — rather than registration refusal.**
   Mechanism named in this repo's own commit `73c2fbf8` (X15): it closes *"the gap the widget's ~30MB
   memory budget couldn't previously afford."* Before X15, `WidgetIntentSupport.makePersistence()`
   called `GatedPersistenceResolver(appGroupID:)` with **no role**, and `StoreConfiguration
   .appGroupOnDisk` armed `cloudKitContainerOptions` whenever the persisted mode was `.iCloudSync`.
   **Every build from 2026-07-01 through b91 stood up a CloudKit-mirroring container inside the widget
   process on any cold-cache miss.** Requires no undocumented Apple behavior, explains both symptoms,
   spans both platforms, and leaves retrievable on-device evidence.
   Related: `timeline(for:in:)` has **no timeout**, and `WidgetIntentSupport.Cache` awaits a single
   in-flight build task — a blocked `PersistenceController` init blocks every caller until WidgetKit's
   budget expires.
2. **The b91→b92 boundary** — the only boundary with a confirmed bad observation on the far side, and
   where six widget-behavior commits land (X5, X6 ×2, X8, X11, X15). X5 changes the cache-population
   semantics the render fast path depends on.

## What would discriminate (cheapest first; 1–3 need no build)

1. **Device crash + jetsam logs — highest-value datum in the investigation.**
   Settings → Privacy & Security → Analytics & Improvements → Analytics Data; look for
   `LillistWidget-*.ips` and `JetsamEvent-*.ips` naming `app.lillist.Widget`. A report **refutes
   "never loads" outright** and points at the pre-X15 mirroring path. Their absence across a period
   covering several forced reloads would be the first real evidence the registration tail has ever had.
2. **Establish the observation context** — was the screenshot the home screen, the widget gallery, or
   the "Edit Widget" sheet? `GRID.md` never records it and the readings differ. Also: does the widget
   still appear in the Add Widget gallery, and can a **fresh** one be added? If yes, the extension is
   being launched and H1's first link is broken.
3. **Reconcile "No Tags."** Was that sheet Lillist's widget, or a Shortcuts-app widget / Control /
   Smart Stack showing `AddTaskIntent` (`Title / Deadline / Tags / Notes`)? `AddTaskIntent` has
   `systemProtocols: []` and is **not eligible** to configure a widget, so the fallback story is not a
   described mechanism.
4. **Toggle the SDK by installing b86** — staged and OTA-installable right now at
   `~/Library/Application Support/deployit/serve/lillist-ios-20260719-142617-e68d88a4/Lillist.ipa`
   (SDK 26.5, identical widget source to b87, valid ad-hoc profile). **Confound:** b86 also predates
   X5/X6/X8/X15, so a clean read needs **b91** as the middle point
   (`lillist-ios-20260722-103748-baea6688` — SDK 27, pre-X15).
5. Console.app attached to the iPhone during a forced widget reload.
6. `xcrun simctl spawn <26.x sim> pluginkit -m -A -D -i app.lillist.Widget` against simulator builds
   from each toolchain.

## Reporter-recall caution

The macOS widget **provably never worked**, yet the report says "it worked previously" for both
platforms. "It worked previously" and the "No Tags" string should both be discounted on iOS until
independently confirmed.

## Investigation hygiene

- Repro gate: **PASSED for LIL-92 (macOS), NOT MET for LIL-91 (iOS)** — see `REPRO.md`'s banner.
- One new untracked test file exists: `Packages/LillistCore/Tests/LillistCoreTests/Widgets/
  WidgetExtensionRegistrationReproTests.swift`. It is **LIL-92's** repro, not LIL-91's. It requires
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; under the default Xcode 26.6,
  `LillistCore` fails to compile (`WatermarkRegistry.swift:56`, non-`Sendable NSPersistentHistoryToken`)
  and the run exits 1 with **zero tests executed** — a false red. Grep the output for
  `Executed 1 test, with 1 failure`, never trust the exit code alone.
- No production code was modified at any point in this investigation.
