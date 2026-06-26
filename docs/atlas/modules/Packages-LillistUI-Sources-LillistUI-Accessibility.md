---
module: Packages/LillistUI/Sources/LillistUI/Accessibility
summary: "Accessibility environment adapters, snapshot-test override keys, AX announcements, and WCAG contrast math"
read_when: "Touching animations, motion gating, or AX"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift
    blob: 616dac83a2a74bce122b17f5902762e17e6c1aed
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift
    blob: 6481f0dc2de465c4f63181e1e2e120456363e8b5
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift
    blob: 01dd8f7355b5e7998307adc84d6c30f53ee618d8
references_modules: [Packages-LillistUI-Sources-LillistUI-Settings]
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistUI/Sources/LillistUI/Accessibility

## Purpose

Centralises accessibility-aware UI primitives for LillistUI: motion-gated animation, transparency-gated material backgrounds, cross-platform VoiceOver announcement posting, WCAG contrast math, and a cross-platform boolean bridge for the Increase Contrast preference. The module's secondary purpose is snapshot-test determinism — because the SDK exposes preference flags as read-only environment values, it introduces an internal override-key layer so tests can lock any accessibility state without touching system settings. Without this module every view would reinvent the reduce-motion guard, duplicate the `colorSchemeContrast == .increased` comparison, and call platform-specific announcement APIs directly.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AccessibilityAnnouncements` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:16` | Cross-platform VoiceOver/NSAccessibility announcement dispatcher; `@MainActor`; no-ops safely when no NSApp instance exists under unit tests. |
| `ContrastMath` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:4` | Namespace for WCAG 2.x sRGB contrast helpers; stateless pure math; used by TagTint for accessible tag color selection and by snapshot tests for ratio assertions. |
| `ContrastTuned` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:138` | Namespace for picking between two values based on the Increase Contrast setting; `@MainActor`, must be called from view context; returns `increased` when the preference is active, else `standard`. |
| `DifferentiateWithoutColorOverrideKey` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:47` | Internal EnvironmentKey backing `differentiateWithoutColorOverride`; default nil means pass-through to system value; injectable only via `@testable import LillistUI`. |
| `EnvironmentValues` | extension | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:14` | Adds `accessibilityShouldIncreaseContrast: Bool` — cross-platform boolean computed from `colorSchemeContrast == .increased`; callers skip the enum comparison. |
| `EnvironmentValues` | extension | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:55` | Adds four internal `*Override: Bool?` computed properties (reduceMotion, reduceTransparency, differentiateWithoutColor, increaseContrast); nil means passthrough to system value; non-nil is injected by snapshot tests for deterministic accessibility baselines. |
| `IncreaseContrastOverrideKey` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:51` | Internal EnvironmentKey backing `increaseContrastOverride`; default nil defers to system; non-nil is injected by snapshot tests for deterministic contrast paths only. |
| `Priority` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:17` | Sendable two-case priority: `.low` for completion confirmations, `.high` for time-sensitive errors; maps to NSAccessibilityPriorityLevel.high / .medium on macOS. |
| `ReduceMotionOverrideKey` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:39` | Internal EnvironmentKey backing `reduceMotionOverride`; default nil defers to system; non-nil overrides for snapshot tests only; invisible outside LillistUI without `@testable import`. |
| `ReduceTransparencyOverrideKey` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:43` | Internal EnvironmentKey backing `reduceTransparencyOverride`; default nil defers to system; non-nil is snapshot-test-only injection. |
| `View` | extension | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:83` | Public View extension providing `accessibleAnimation` and `accessibleMaterial`; the sole public callsite API for motion and transparency adaptation across LillistUI. |
| `accessibleAnimation` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:87` | Applies animation normally; passes nil when reduce-motion is active (override wins over system). Use for decorative transitions only — gate state-communicating animations explicitly per comment at line 86. |
| `accessibleMaterial` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:93` | Applies `material` as background; substitutes opaque `fallback` (clipped to `shape`) when reduce-transparency is active; override wins over system value. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:112` | ViewModifier body for AccessibleAnimationModifier; reads override-then-system reduce-motion flag and forwards nil or the requested animation to `.animation(_:value:)`. |
| `body` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:125` | ViewModifier body for AccessibleMaterialModifier; reads override-then-system reduce-transparency flag and applies material or opaque fallback as background. |
| `channel` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:8` | Nested sRGB gamma-linearization closure inside `relativeLuminance`; applies the IEC 61966-2-1 transfer curve; not independently callable from outside the enclosing function. |
| `hsbToRGB` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:20` | Converts HSB color to (r,g,b) triple in [0,1]; pure math, no state; inverse of TagTint.rgbToHSB; handles achromatic case (saturation == 0) by returning brightness for all channels. |
| `post` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:20` | `@MainActor`; posts accessibility announcement cross-platform (UIKit: AccessibilityNotification.Announcement; AppKit: NSAccessibility.announcementRequested); no-ops when NSApp is nil. |
| `relativeLuminance` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:7` | WCAG 2.x relative luminance for sRGB inputs in [0,1]; output feeds `wcagRatio`; 4.5:1 is the AA threshold for normal body text. |
| `value` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:140` | `@MainActor`; returns `increased` when `accessibilityShouldIncreaseContrast` is true in the supplied EnvironmentValues, else `standard`; argument order is (standard, increased). |
| `wcagRatio` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:14` | Computes WCAG contrast ratio from two luminance values; order-independent (picks lighter/darker internally); 4.5:1 is AA body-text threshold, 3:1 is AA large-text threshold. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibleAnimationModifier -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`
- `Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibleMaterialModifier -> Packages-LillistUI-Sources-LillistUI-Settings.Environment (reads)`

## Type notes

All types are stateless: the two private ViewModifier structs hold only let-bound values injected at call site, and `ContrastMath`/`AccessibilityAnnouncements` are caseless enums used as pure namespaces — no lifecycle, no shared mutable state. `AccessibilityAnnouncements.post` and `ContrastTuned.value` are `@MainActor`; they must be called from a view or main-actor context (Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:19, Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:139). The four `*OverrideKey` structs are `internal` (not `public`), making them invisible outside LillistUI without `@testable import` — this is the enforcement boundary preventing production code from accidentally pinning accessibility state (Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:36-37). `ContrastMath` functions are `public static` pure math — thread-safe, callable from any actor context.

## External deps

- AppKit — imported
- Foundation — imported
- SwiftUI — imported
- UIKit — imported

## Gotchas

SDK 26.2 exposes accessibility env values (reduceMotion, reduceTransparency, etc.) as read-only — `.environment(_:_:)` cannot override them in snapshot tests. Workaround: four internal `*OverrideKey` EnvironmentKeys default to nil (pass-through); tests inject via `@testable import LillistUI`; production code cannot see them because the keys are `internal` (Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:24-37). `AccessibilityAnnouncements.post` guards `NSApplication.shared` with an optional-cast guard and returns early when nil — prevents crashes in unit tests that have no app instance (Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:25-26).
