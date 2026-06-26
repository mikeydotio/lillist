---
module: "Packages/LillistCore (misc)"
summary: "SwiftPM build plugin that compiles `.xcdatamodeld` to `.momd` so LillistCore entity loading works outside Xcode."
read_when: "Touching Package.swift or model compilation"
sources:
  - path: Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift
    blob: 27b2698783db0258c1ee5297e7219c6b00dfe679
  - path: Packages/LillistCore/README.md
    blob: 3bc2ec5edf6b7b0d049d0dad1562702390d489a1
generator: cartographer/4
baseline: 515f24730d21cb81ca1c9737ffeb981e9c414d3c
---

# Module: Packages/LillistCore (misc)

## Purpose

This module is the SwiftPM build infrastructure for LillistCore: a `BuildToolPlugin` that closes the gap between SwiftPM and Core Data's `momc` compiler so that `swift build` and `swift test` produce a loadable `.momd` bundle without Xcode. It also holds the package README documenting LillistCore's public contract and history. Without this plugin, entity instantiation via `Bundle.module` would fail at runtime in any non-Xcode build.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CompileCoreDataModel` | struct | `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:12` | `BuildToolPlugin` entry point; returns one `.buildCommand` per `.xcdatamodeld` in the target, compiling each to `<name>.spm.momd` in the plugin work directory. |
| `createBuildCommands` | func | `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:13` | Returns `[Command]` with one `xcrun momc` command per `.xcdatamodeld` source file; output is `<name>.spm.momd` in `pluginWorkDirectoryURL`; inner `contents` files are declared as inputs for fine-grained cache invalidation. |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |

## Relationships

## Type notes

`CompileCoreDataModel` conforms to `BuildToolPlugin` (PackagePlugin) and is marked `@main`, running as a sandbox-isolated SwiftPM subprocess during build graph evaluation — not in the app process (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:11-12). `createBuildCommands` is `async throws` per protocol contract but its body is fully synchronous; the async context is inherited from the protocol, not required by the implementation (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:13). Output paths use `context.pluginWorkDirectoryURL`, so compiled `.momd` bundles are ephemeral and regenerated on clean builds (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:32). `modelInputFiles` degrades gracefully on enumeration failure, returning `[]` rather than throwing, so the build falls back to directory-mtime-only invalidation without crashing the plugin (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:76-77).

## External deps

- Foundation — imported
- PackagePlugin — imported

## Gotchas

Output is named `<name>.spm.momd` (not `<name>.momd`) to avoid a "Multiple commands produce" collision with Xcode's built-in `DataModelCompile` rule when the package is embedded in a workspace; callers must check both names (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:28-32). `.xcdatamodeld` directory mtime does NOT update when the inner `*.xcdatamodel/contents` file is edited, so the plugin explicitly enumerates inner `contents` files as `inputFiles` to force `momc` to re-run on real model edits (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:36-43). `.xccurrentversion` is deliberately excluded from tracked inputs — empirically, neither enumerating it (a dotfile) nor declaring it by path makes llbuild re-run `momc` on its mtime change from a SwiftPM build-tool plugin (Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:63-69).
