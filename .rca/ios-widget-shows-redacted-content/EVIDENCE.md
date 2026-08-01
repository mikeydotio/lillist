# EVIDENCE — ios-widget-shows-redacted-content

Facts only. Every line here was observed, not inferred; inferences live in `HYPOTHESES.md`.
Sources: orchestrator direct observation (marked **[O]**) and the qa-engineer's minimization run
(**[Q]**, recorded in `MINIMAL.md`). Nothing on the host was mutated.

## The failure, as measured

| Fact | Source |
|---|---|
| `pluginkit -m -A -D -i app.lillist.Widget` → empty (no matches) | **[O]** |
| `pluginkit -m -p com.apple.widgetkit-extension` → 78 other extensions registered | **[O]** |
| `/Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex` present, signature valid, `spctl -a` → accepted / Notarized Developer ID | **[O][Q]** |
| Repro test: 5/5 deterministic RED (orchestrator), 10/10 (qa-engineer) | **[O][Q]** |

## Eliminated as causes

| Candidate | Disconfirming observation | Source |
|---|---|---|
| Wrong/missing extension point | Installed appex and repo source both declare `NSExtensionPointIdentifier = com.apple.widgetkit-extension` | **[O]** |
| Appex missing from bundle | Present | **[O]** |
| Gatekeeper quarantine | No `com.apple.quarantine` xattr | **[O]** |
| App/appex version skew | macOS app + appex both `0.18.0`/`52`; iOS both `0.19.0`/`92` | **[Q]** |
| Wrong `minos` from the SDK-27 pin | `LC_BUILD_VERSION minos = 26.0` on every archived build back to b83 | **[Q]** |
| Corrupt/changed iOS AppIntents metadata | Shipped `.ipa` b92 vs known-good b88: `Metadata.appintents/extract.actionsdata` semantically identical (only array ordering + generator version differ). `SelectFilterIntent` declares one parameter titled **"Filter"**, entity `SmartFilterEntity`. **No `"Tags"` parameter exists in the widget's metadata.** | **[Q]** |

## The central anomaly

LaunchServices **has** a complete record for the installed extension; PlugInKit does **not** list it.
The two databases disagree.

```
lsregister -dump | grep "/Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex"
  404818: path: … (0xf5b4)

plugin id:   Lillist (0x42dc)          identifier:  app.lillist.Widget
teamID:      VMY8R4T742                base flags:  link-enabled
platform:    native   slices: x86_64 arm64
execSDK ver: 27.0
CFBundleVersion = 52 ; CFBundleShortVersionString = "0.18.0"
NSExtensionPointIdentifier = "com.apple.widgetkit-extension"
```

Distribution of the 22 `LillistWidget-macOS.appex` path records: 19 DerivedData `Debug`, 1
DerivedData archive staging, 1 `/private/tmp/lillist-build-check`, 1 `/Applications`. **[Q]**

## The SDK correlation

Host: **macOS 26.5.2 (25F84)**. All 97 widgetkit-extension bundle IDs in LS, correlated against the
live registry: **[Q]**

| max execSDK | bundle IDs | registered | unregistered |
|---|---|---|---|
| 12.1 / 15.5 / 26.0 / 26.2 / 26.4 | 33 | **33** | **0** |
| 26.5 | 63 | 45 | 18 |
| **27.0** | **1** | **0** | **1** ← `app.lillist.Widget` |

Bounding facts, recorded so the correlation is not oversold:
- n=1 at bundle-ID level; the 8 SDK-27 records are 8 copies of one bundle, not independent samples.
- Of the 18 unregistered 26.5 bundle IDs, 17 are stale paths whose bundle is gone — but one,
  `com.joehribar.toggl.widgets` (Timery), **is installed, alive, and also unregistered**. So
  "installed but unregistered" is not unique to SDK 27.
- The 19 DerivedData Debug records are *all* execSDK 27.0 and *all* unregistered → they do not
  discriminate between "SDK 27" and "not in /Applications".

## Timeline

| When | Event | Source |
|---|---|---|
| 2026-07-01 | Widget feature ships | CLAUDE.md |
| 2026-07-15 | `v0.14.1` — last release in the SDK **26.2** era (widget demonstrably worked) | **[Q]** |
| 2026-07-19 | `v0.15.0` — LS holds **both** 26.5 and 27.0 records for this version | **[Q]** |
| 2026-07-20 18:09 | `v0.16.0` — execSDK 27.0 | **[Q]** |
| 2026-07-21 05:07Z | `LIL-4` "On-device widget verification" closed **done** | **[O]** |
| 2026-07-21 15:52 | `v0.17.0` — execSDK 27.0 | **[Q]** |
| 2026-07-21 **22:59** | `716981a9 build(deploy): pin Xcode 27 via repo .deployit/config.toml` | **[O]** |
| 2026-07-21 **23:30** | `v0.18.0` tagged — **31 minutes after the pin**; build 52 = the installed macOS app | **[O]** |
| 2026-07-29 | `v0.19.0` / build 92 iOS deployed; macOS build 56 published but **never installed** | **[O]** |

**Tension to resolve:** Xcode 27 was already in use from ~`v0.15.0`/`v0.16.0` (2026-07-19/20),
*before* the `config.toml` pin merely automated it — and that predates `LIL-4`'s on-device
verification closing done on 07-21. Either LIL-4 was verified earlier than it was closed, verified
on iOS only, or the SDK correlation does not tell the whole story. Unresolved.

## Toolchain fact (affects any future run of this repro)

Under the `xcode-select` default (Xcode 26.6), `LillistCore` **fails to compile** —
`WatermarkRegistry.swift:56`, non-`Sendable` `NSPersistentHistoryToken` — and `swift test` exits **1
with zero tests executed**. Exit code alone cannot distinguish a genuine RED from a build failure;
grep the output for `Executed 1 test, with 1 failure` **and** `is NOT registered with the system`.
This also contradicts `CLAUDE.md`'s claim that the 26.6 default "builds the whole app". **[O][Q]**

## Not yet gathered

- Any iOS-side registration evidence. Every fact above is macOS; the report and screenshot are iOS.
- Whether a locally-built macOS app registers today. Blocked: the source cannot build against SDK
  26.x at all, so the SDK variable cannot be toggled without code changes, and building + letting LS
  pick up the product would mutate the registry. **Escalated, not performed.**
- Why Timery's widget is also unregistered.
