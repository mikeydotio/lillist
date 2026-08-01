# REPRO — ios-widget-shows-redacted-content

> ## ⚠️ SUPERSEDED — this gate reproduces a DIFFERENT defect
>
> This test observes the **macOS** host and reproduces what is now filed as **LIL-92**: the macOS
> widget extension ships without `com.apple.security.app-sandbox` (it shares the iOS entitlements
> file) and therefore never registers. That defect is **longstanding** — the key has never existed
> in `Extensions/LillistWidget/Lillist.entitlements` since 2026-07-01 — and it is **macOS-only**,
> because iOS extensions do not require sandboxing.
>
> It is therefore **not** a gate for the reported **iOS regression** (LIL-91). The iOS side has
> **no reproduction yet**. Per the user's decision (2026-07-30), macOS is dropped from this
> investigation and the RCA is re-aimed at iOS.
>
> The measurements below remain valid *for LIL-92* and are retained as its evidence.
> Everything downstream that depends on an **iOS** oracle must treat the gate as **NOT MET**.

**Gate status (LIL-92, macOS): PASSED** (deterministic automated failing test, failure_rate 1.0).
**Gate status (LIL-91, iOS): NOT MET.**

## Command

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --package-path Packages/LillistCore \
  --filter WidgetExtensionRegistrationReproTests
```

Test file (NEW, untracked): `Packages/LillistCore/Tests/LillistCoreTests/Widgets/WidgetExtensionRegistrationReproTests.swift`
Test id: `LillistCoreTests.WidgetExtensionRegistrationReproTests/testInstalledMacWidgetExtensionIsRegisteredWithPluginKit`

## Failure rate

| Batch | Runs | Failures | Rate |
|---|---|---|---|
| Initial verify | 1 | 1 | 1.0 |
| Determinism batch | 3 | 3 | 1.0 |
| Final (self-contained cmd form) | 1 | 1 | 1.0 |
| **Total** | **5** | **5** | **1.0 — deterministic** |

## Diagnostic signal (failure tail excerpt)

```
WidgetExtensionRegistrationReproTests.swift:73: error:
  -[LillistCoreTests.WidgetExtensionRegistrationReproTests
    testInstalledMacWidgetExtensionIsRegisteredWithPluginKit] :
  XCTAssertFalse failed - The installed Lillist macOS widget extension is NOT
  registered with the system.

    queried:  pluginkit -m -A -D -i app.lillist.Widget   → no matches
    on disk:  /Applications/Lillist.app/Contents/PlugIns/LillistWidget-macOS.appex
              (present, signature valid)
    registry: 78 other com.apple.widgetkit-extension extensions ARE registered

Executed 1 test, with 1 failure (0 unexpected) in 0.290 seconds
```

## Ties to GRID.md

Maps to **WHAT-IS** / **distinction 2**: the on-screen entry is the *placeholder* entry and
`WidgetUnavailableView` is never reached, i.e. `timeline(for:in:)` is not returning `nil` — it is
not completing at all. An extension absent from the WidgetKit registry is never launched, so the
timeline provider never runs, which is the most literal available reading of that cell. It also
covers **distinction 1** ("No Tags"): with the widget's own `SelectFilterIntent` unregistered, the
configuration UI resolves against the app's other AppIntents surface, whose unset
`AddTaskIntent.tags: [String]?` is exactly how AppIntents renders "No Tags".

## Orchestrator-verified facts (checked independently, not taken from the agent)

```
/Applications/Lillist.app                                    → present
/Applications/Lillist.app/Contents/PlugIns/                  → LillistWidget-macOS.appex
pluginkit -m -A -D -i app.lillist.Widget                     → EMPTY (no matches)
pluginkit -m -p com.apple.widgetkit-extension | wc -l        → 78
pluginkit -m -A -D | grep -i lillist                         → EMPTY (exit 1)
```

The last line is **broader than the agent reported**: it is not only the widget that is
unregistered — *no Lillist extension of any kind* appears in the pluginkit registry on this Mac.
That widening is a diagnose-step input, deliberately not interpreted here.

## Gotcha: the gate false-reds under the default toolchain

The first verification run used the `xcode-select` default (`/Applications/Xcode.app`, 26.6) and
returned exit 1 / failure_rate 1.0 — but for the **wrong reason**: the `LillistCore` compile
aborted with `error: fatalError` and **zero tests executed**. That is a false repro and was
rejected. `DEVELOPER_DIR` pointing at the Xcode 27 beta is mandatory for this command.

Note this contradicts `CLAUDE.md`'s *Two Xcode toolchains* section, which currently asserts the
26.6 default "builds the **whole app**". On this machine, today, 26.6 cannot compile `LillistCore`
at all. Flagged for correction; **not** assumed relevant to the defect (though the deployit
`min_sdk = "27"` toolchain pin is already in GRID.md's aligned changes and diagnose should weigh it).

## Limitations — carry these forward

1. **macOS-only observation.** The report originated on iOS; this test observes the *installed
   macOS app*. The iOS widget's registration state on the physical iPhone is unverified. The gate
   is met for the cross-platform failure, not specifically for the iOS device.
2. **Not hermetic.** It inspects `/Applications/Lillist.app` on this host. All preconditions
   `XCTSkip` rather than fail, so a machine without the app reports inconclusive instead of a false
   red — but it is an environment probe, not a unit test.
3. **Causally upstream of the visible symptom.** It asserts on registration, not on rendered
   pixels. It is a proxy: strong, deterministic, and mechanism-level, but a green here would not by
   itself prove the widget renders real tasks.
4. **Weakly green-able.** Manually re-registering the extension (e.g. `pluginkit -a`) would flip it
   green without fixing any root cause. The eventual regression test must not be satisfiable that
   way — a fix-step concern, recorded now so it is not forgotten.
5. **Placement is provisional.** A `LillistCore` unit-test target asserting on an installed `.app`
   is architecturally odd. Re-home it before it becomes the permanent regression test.

## Not yet minimized

`MINIMAL.md` is not written. Minimization is a FULL-tier step and the tier is still unset.
