---
module: "Packages/LillistUI/Sources/LillistUI (misc)"
summary: "LillistUI package root: namespace enum, version constant, Plus Jakarta Sans font, and string catalog"
read_when: "Orienting in LillistUI or string catalog"
sources:
  - path: Packages/LillistUI/Sources/LillistUI/LillistUI.swift
    blob: 6c093e3ce4c0bfbbd190533a80b07af79b36b648
  - path: Packages/LillistUI/Sources/LillistUI/Resources/Fonts/OFL.txt
    blob: ea69b0ca12a02556c436680ea0a159efb7a748fa
  - path: Packages/LillistUI/Sources/LillistUI/Resources/Localizable.xcstrings
    blob: 67986e6b1f86a8d5722ad0af91983cecf17041ee
generator: cartographer/4
baseline: 99321d774840d17affd02fe2ac63b01b3d8cbec3
---

# Module: Packages/LillistUI/Sources/LillistUI (misc)

## Purpose

The LillistUI package root: defines the `LillistUI` namespace enum with a `version` constant that serves as the library's versioned identity, bundles the Plus Jakarta Sans typeface under the SIL OFL, and owns the shared `Localizable.xcstrings` catalog that all user-visible strings in the library key into. The doc comment on `LillistUI` (Packages/LillistUI/Sources/LillistUI/LillistUI.swift:3–41) enumerates every sub-module — Components, Theme, Accessibility, Recurrence, QuickCapture, Status, iOS — making it the primary orientation surface for the library. Without it the package has no single versioned identity, no localization anchor, and no discoverable sub-module index.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `LillistUI` | enum | `Packages/LillistUI/Sources/LillistUI/LillistUI.swift:42` | Caseless namespace; callers may read `LillistUI.version` for the library SemVer string; never instantiate — no cases, no mutable state. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

`LillistUI` (Packages/LillistUI/Sources/LillistUI/LillistUI.swift:42) is a caseless `public enum` used as a non-instantiable namespace — no actor isolation, no mutable state. It carries one constant `public static let version = "0.1.0"` (line 45), a hardcoded string not wired to the repo's VERSION file. `Localizable.xcstrings` is the xcstrings-format string catalog for all user-visible strings in LillistUI; per project convention it must stay aligned with the iOS-app and macOS-app catalogs. `Resources/Fonts/OFL.txt` records the SIL Open Font License for the bundled Plus Jakarta Sans typeface.

## External deps

- Foundation — imported
- source — imported
- the — imported
