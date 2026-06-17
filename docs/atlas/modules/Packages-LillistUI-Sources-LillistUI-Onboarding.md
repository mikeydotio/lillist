---
module: Packages/LillistUI/Sources/LillistUI/Onboarding
summary: "Pure-presentation onboarding and iCloud-gate screens shared across iOS and macOS app targets"
read_when: "Touching first-launch flow"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift
    blob: 3acdc95019c18123523312efbae30d9db650300b
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift
    blob: ecd20cfa8508fe993115a13f1a7a2b47ec101f9b
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift
    blob: 91b2fd39738ad697fbef83ee270080719b69e1ba
references_modules: [Packages-LillistCore-Sources-LillistCore-Notifications, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Onboarding

## Purpose

Holds the platform-neutral body content for first-launch surfaces so iOS and
macOS render identical copy and font treatment. The design idea is a
content/wrapper split: shared layout and strings live here, while deep-link
URLs, header sizing, and action-bar shape stay in the app-target wrappers
because they diverge enough that sharing them would add more conditionals than
it removes (`Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:9`).
Without this module the welcome and iCloud-unavailable wording would drift
between platforms — the exact drift these types were lifted to fix
(`Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift:9`).

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `ICloudRequiredContent` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift:12` | Shared "iCloud is required" body (heading, copy, optional `lastError`); wrapper supplies the action bar |
| `ICloudUnavailableScreen` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:11` | Full-screen LocalOnly info screen; pure presentation with one `onContinue` action closure |
| `OnboardingContent` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:13` | Shared onboarding body: feature bullets + permission-status row driven by `permissionStatus` |
| `OnboardingContent.Bullet` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:14` | `Identifiable`/`Equatable` value type (`icon`, `text`) callers pass to populate the bullet list |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `permissionRow` | computed var | `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:60` | The only behavioral branch in the module; switches `authorized`/`denied`/`notDetermined` to surface the Open Settings affordance |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent -> Packages-LillistCore-Sources-LillistCore-Notifications.NotificationPermissions (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Components.DotGridBackdrop (calls)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudRequiredContent -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.OnboardingContent -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowPalette (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistColor (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistSpacing (reads)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-2.LillistTypography (reads)`

## Type notes

All three are `View` structs with public memberwise `init`s (Swift's synthesized
init is internal-only, so callers outside the package need the hand-written one —
e.g. `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:28`).
The structs are pure presentation: no `@State`, no `.task`; data and action
closures arrive through `init`, and the host wires `onContinue`/`onOpenSettings`
to advance onboarding state (`Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:9`).
`OnboardingContent.Bullet` carries a `UUID` `id` for `ForEach` identity
(`Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:15`).

`ICloudUnavailableScreen` (Plan 21) and `ICloudRequiredContent` serve different
scenarios: `ICloudUnavailableScreen` is the non-blocking informational screen
shown when iCloud is absent but the app runs locally; `ICloudRequiredContent`
is the older blocking-content fragment retained for the per-platform wrapper
that still gates iCloud-required contexts.

## External deps

- SwiftUI — `View` conformance, layout, `ForEach`, SF Symbols for all three surfaces
- LillistCore — `import LillistCore` in `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:2` for `NotificationPermissions.AuthorizationStatus`

## Gotchas

- `ICloudUnavailableScreen` renders `DotGridBackdrop()` (`Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:49`), which uses `.drawingGroup()` / Metal and blanks the entire offscreen capture; this screen cannot be snapshot-tested offscreen and requires app-hosted or manual verification.
