---
module: Packages/LillistUI/Sources/LillistUI/Onboarding
summary: "Pure-presentation onboarding views: iCloud gate content, LocalOnly fallback screen, and feature/permission bullets"
read_when: "Touching first-launch or iCloud gate"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift
    blob: 3acdc95019c18123523312efbae30d9db650300b
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift
    blob: ecd20cfa8508fe993115a13f1a7a2b47ec101f9b
  - path: Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift
    blob: 91b2fd39738ad697fbef83ee270080719b69e1ba
references_modules: [Packages-LillistUI-Sources-LillistUI-Components-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-1]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Onboarding

## Purpose

The Onboarding module provides three pure-presentation SwiftUI views that gate or inform the user before the main app UI is accessible: a legacy iCloud-required blocker (`ICloudRequiredContent`), a Plan 21 informational screen for the LocalOnly fallback (`ICloudUnavailableScreen`), and a cross-platform feature-bullets + notification-permission view (`OnboardingContent`). Every view is stateless and closure-driven — all data and actions flow in through `init` with no `@State` or environment reads, consistent with the container/presenter split used across LillistUI. Without this module, both app targets lose their first-launch gates and the shared notification-permission status surface that bridges the iOS and macOS onboarding wrappers.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `Bullet` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:14` | Immutable feature-bullet value (SF Symbol name + display text); `id` is a fresh `UUID()` assigned at init, so two equal-content instances are never `==` equal. |
| `ICloudRequiredContent` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift:12` | Renders iCloud-required heading, descriptive copy, and optional error line; callers supply `lastError` and own the action bar. |
| `ICloudUnavailableScreen` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:11` | Informational full-screen view for LocalOnly fallback; fires `onContinue` on the single 'Continue' button tap, no other side effects. |
| `OnboardingContent` | struct | `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:13` | Renders caller-supplied feature bullets and notification permission status row; pure presentation — never requests permissions, fires `onOpenSettings` only when status is `.denied`. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Components-chunk-1.DotGridBackdrop (calls)`
- `Packages-LillistUI-Sources-LillistUI-Onboarding.ICloudUnavailableScreen -> Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.rainbow (calls)`

## Type notes

All three public views are pure value types with no `@State`, no `.task`, and no environment reads (`Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudRequiredContent.swift:12-38`, `Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:11-52`, `Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:13-46`). Data flows in through public `init` parameters; actions are `@escaping () -> Void` closures. `OnboardingContent` accepts `NotificationPermissions.AuthorizationStatus` from LillistCore (`Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:25`) and renders it read-only via a `@ViewBuilder permissionRow` — it never requests or mutates permission state. `Bullet.id` is assigned via `UUID()` at construction time (`Packages/LillistUI/Sources/LillistUI/Onboarding/OnboardingContent.swift:15`); because synthesized `Equatable` compares all stored properties including `id`, two `Bullet` instances with identical `icon`+`text` are NOT `==` equal. All views are `@MainActor`-isolated through their `View` conformance.

## External deps

- LillistCore — imported
- SwiftUI — imported

## Gotchas

`ICloudUnavailableScreen` uses `DotGridBackdrop()` as its background layer (`Packages/LillistUI/Sources/LillistUI/Onboarding/ICloudUnavailableScreen.swift:49`). `DotGridBackdrop` is a Metal-backed (`.drawingGroup()`) surface that blanks the entire view hierarchy during offscreen snapshot capture — this screen cannot be snapshot-tested with the standard offscreen `LillistUITests` strategy; host it in the app-hosted glass snapshot suite instead.
