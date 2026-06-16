---
module: Packages/LillistUI/Sources/LillistUI/Accessibility
summary: "Accessibility primitives — Reduce Motion/Transparency/Contrast view helpers, AX announcements, WCAG contrast math"
read_when: "Reduce Motion, AX, contrast"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift
    blob: 616dac83a2a74bce122b17f5902762e17e6c1aed
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift
    blob: 6481f0dc2de465c4f63181e1e2e120456363e8b5
  - path: Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift
    blob: 01dd8f7355b5e7998307adc84d6c30f53ee618d8
references_modules: [Packages-LillistUI-Sources-LillistUI-Theme-chunk-1, Packages-LillistUI-Sources-LillistUI-Theme-chunk-2, Packages-LillistUI-Sources-LillistUI-Components, Packages-LillistUI-Sources-LillistUI-iOS-misc, Packages-LillistUI-Sources-LillistUI-iOS-Tasks, Packages-LillistUI-Sources-LillistUI-DragReorder, Apps-Lillist-iOS-Sources-Detail, Apps-Lillist-iOS-misc, Apps-Lillist-macOS-Sources-Views-Detail]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistUI/Sources/LillistUI/Accessibility

## Purpose

The accessibility seam for LillistUI: it normalizes Apple's per-platform
Accessibility settings into the binary shapes the UI actually consumes, and
gives every callsite one canonical way to honor Reduce Motion, Reduce
Transparency, and Increase Contrast. It exists so individual views never
re-implement `colorSchemeContrast == .increased` or the iOS-vs-macOS
announcement split, and so snapshot tests can deterministically lock those
env-honoring paths via internal override keys without touching production code.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `AccessibilityAnnouncements` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:16` | Namespace for posting VoiceOver/AX announcements cross-platform |
| `AccessibilityAnnouncements.post` | static func | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:20` | `@MainActor`; post `message` at `.low`/`.high`; no-ops with no NSApp on macOS |
| `AccessibilityAnnouncements.Priority` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:17` | `Sendable` `.low`/`.high`; maps to NSAccessibility medium/high on macOS |
| `ContrastMath` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:4` | WCAG 2.x contrast helper namespace |
| `ContrastMath.hsbToRGB` | static func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:20` | HSB→RGB; inverse of `TagTint.rgbToHSB` |
| `ContrastMath.relativeLuminance` | static func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:7` | sRGB relative luminance for channels in [0,1] |
| `ContrastMath.wcagRatio` | static func | `Packages/LillistUI/Sources/LillistUI/Accessibility/ContrastMath.swift:14` | Contrast ratio of two luminances; 4.5 is the AA body-text floor |
| `ContrastTuned` | enum | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:138` | Picks `standard`/`increased` value from an `EnvironmentValues` |
| `ContrastTuned.value` | static func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:140` | `@MainActor`; returns `increased` iff contrast is raised |
| `EnvironmentValues.accessibilityShouldIncreaseContrast` | computed var | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:19` | Cross-platform bool for "Increase Contrast"; `colorSchemeContrast == .increased` |
| `View.accessibleAnimation` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:87` | `.animation(_:value:)` that no-ops under Reduce Motion |
| `View.accessibleMaterial` | func | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:93` | Material background; opaque `fallback` under Reduce Transparency |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `AccessibleAnimationModifier` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:106` | Implements `accessibleAnimation`; reads override-then-system Reduce Motion |
| `AccessibleMaterialModifier` | struct | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:118` | Implements `accessibleMaterial`; swaps material for fallback under Reduce Transparency |
| `reduceMotionOverride` | computed var | `Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:59` | Internal env key; snapshot tests inject a deterministic Reduce Motion value |

## Relationships

- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.TagTint -> Packages-LillistUI-Sources-LillistUI-Accessibility.ContrastMath (calls)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.RainbowToggleStyle -> Packages-LillistUI-Sources-LillistUI-Accessibility.EnvironmentValues (reads)`
- `Packages-LillistUI-Sources-LillistUI-Theme-chunk-1.StatusPalette -> Packages-LillistUI-Sources-LillistUI-Accessibility.EnvironmentValues (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.StatusCubeView -> Packages-LillistUI-Sources-LillistUI-Accessibility.EnvironmentValues (reads)`
- `Packages-LillistUI-Sources-LillistUI-Components.TagChipView -> Packages-LillistUI-Sources-LillistUI-Accessibility.EnvironmentValues (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-Tasks.FilterChip -> Packages-LillistUI-Sources-LillistUI-Accessibility.EnvironmentValues (reads)`
- `Packages-LillistUI-Sources-LillistUI-iOS-misc.QuickCaptureDialogPresenter -> Packages-LillistUI-Sources-LillistUI-Accessibility.View (calls)`
- `Packages-LillistUI-Sources-LillistUI-DragReorder.DragOverlay -> Packages-LillistUI-Sources-LillistUI-Accessibility.View (calls)`
- `Apps-Lillist-iOS-Sources-Detail.RecurrenceSheet -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`
- `Apps-Lillist-macOS-Sources-Views-Detail.TaskDetailView -> Packages-LillistUI-Sources-LillistUI-Accessibility.AccessibilityAnnouncements (calls)`
- `Apps-Lillist-iOS-misc.OnboardingScreen -> Packages-LillistUI-Sources-LillistUI-Accessibility.View (calls)`

## Type notes

All public surfaces are pure namespaces (`enum`) or `View`/`EnvironmentValues`
extensions — no instances, no stored state, no actor isolation beyond the
`@MainActor` on `post` and `ContrastTuned.value`. The two modifier structs are
`private` and own no state; each reads its `*Override` env key first and falls
back to the system AX value (`Packages/LillistUI/Sources/LillistUI/Accessibility/AccessibilityEnvironment.swift:113`),
so production never sets the override (the keys are `internal`, not `public`).
`AccessibilityAnnouncements.post` is `#if`-branched: iOS routes to
`AccessibilityNotification.Announcement`, macOS to `NSAccessibility.post`; with
no `NSApplication.shared` (unit tests) the macOS branch no-ops by design
(`Packages/LillistUI/Sources/LillistUI/Accessibility/Announcements.swift:26`).
`accessibilityShouldIncreaseContrast` is the synthesized binary view over the
SDK's read-only `colorSchemeContrast`, which exists because the boolean
`accessibilityShouldIncreaseContrast` SDK key is iOS-only.

## External deps

- SwiftUI — `EnvironmentValues`/`View`/`ViewModifier`, `colorSchemeContrast`, the AX env keys
- UIKit — `AccessibilityNotification.Announcement` for iOS announcements (under `#if canImport(UIKit)`)
- AppKit — `NSAccessibility.post`, `NSApplication` for macOS announcements (under `#if canImport(AppKit)`)
