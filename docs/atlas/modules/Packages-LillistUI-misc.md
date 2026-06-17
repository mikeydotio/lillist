---
module: "Packages/LillistUI (misc)"
summary: "SwiftPM manifest for the LillistUI library — products, platforms, deps, and build flags"
read_when: "Changing LillistUI package structure, dependencies, platforms, or build flags"
sources:
  - path: Packages/LillistUI/Package.swift
    blob: dc98b12e06978bcdd28655daba94b87bb242f502
references_modules: [Packages-LillistCore-misc]
generator: cartographer/1
baseline: 1a1562b636e43ebbdc35c7939ab6989b387f50e9
verified: true
---

# Module: Packages/LillistUI (misc)

## Purpose

The SwiftPM manifest that defines the `LillistUI` package: the cross-platform
SwiftUI library shared by both apps and the share extension. It declares the
single `LillistUI` library product, pins the minimum macOS/iOS platforms,
wires the local `LillistCore` dependency and the snapshot-testing dependency,
and sets the strict-concurrency + warnings-as-errors build posture that the
rest of the package is compiled under. Without this file there is no package.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `package` | manifest | `Packages/LillistUI/Package.swift:4` | The `Package` value SwiftPM resolves; exposes the `LillistUI` library product |

## Load-bearing internals

(none — a manifest file has no internal symbols worth ranking)

## Relationships

- `Packages-LillistUI-misc.package -> Packages-LillistCore-misc.package (reads)`

## Type notes

The `LillistUI` target enables the `StrictConcurrency` experimental feature and
treats all warnings as errors (`Packages/LillistUI/Package.swift:27`), matching
the project's strict-concurrency-on-source posture. The `LillistUITests`
test target keeps warnings-as-errors but does not enable strict concurrency
(`Packages/LillistUI/Package.swift:46`). Bundled assets are processed from the
`Resources` directory (`Packages/LillistUI/Package.swift:25`). The test target
`exclude`s six `__Snapshots__` reference-image directories from compilation
(`Packages/LillistUI/Package.swift:38`).

## External deps

- swift-snapshot-testing — snapshot assertion library, test target only (`Packages/LillistUI/Package.swift:16`)
- LillistCore — local sibling package providing the data layer and DTOs (`Packages/LillistUI/Package.swift:15`)
