---
module: "Packages/LillistCore (misc)"
summary: "SwiftPM manifest, Core Data model-compile build plugin, and package README for LillistCore"
read_when: LillistCore package/plugin
sources:
  - path: Packages/LillistCore/Package.swift
    blob: 2114f2075b73500bfe780910899b44aa96568927
  - path: Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift
    blob: 27b2698783db0258c1ee5297e7219c6b00dfe679
  - path: Packages/LillistCore/README.md
    blob: 3bc2ec5edf6b7b0d049d0dad1562702390d489a1
references_modules: [Packages-LillistCore-Sources-LillistCore-Persistence, Packages-LillistCore-Sources-LillistCore-Model]
generator: cartographer/1
baseline: 85a4dc8648a4280e30f533268d65bfac16701d21
verified: true
---

# Module: Packages/LillistCore (misc)

## Purpose

The package-level scaffolding for LillistCore: the SwiftPM manifest that declares
the library + `lillist` CLI targets and their build settings, and the build-tool
plugin that closes SwiftPM's gap around Core Data. SwiftPM never invokes `momc`
on `.xcdatamodeld` resources, so `CompileCoreDataModel` shells out to `xcrun momc`
at build time; without it the package would ship no compiled model and the
persistence layer would fail to load `NSEntityDescription`s at runtime.

## Public API

| Symbol | Kind | Location | Contract |
| --- | --- | --- | --- |
| `CompileCoreDataModel` | struct | `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:12` | `@main` BuildToolPlugin; emits a `momc` command per `.xcdatamodeld` on the target |
| `createBuildCommands(context:target:)` | func | `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:13` | BuildToolPlugin entry; maps each model dir to a `xcrun momc` build command |

## Load-bearing internals

| Symbol | Kind | Location | Why it matters |
| --- | --- | --- | --- |
| `modelInputFiles(in:)` | func | `Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:70` | Declares each inner `*.xcdatamodel/contents` as an llbuild input so a model edit invalidates `momc` |

## Relationships

- `Packages-LillistCore-misc.CompileCoreDataModel -> Packages-LillistCore-Sources-LillistCore-Model (reads)`
- `Packages-LillistCore-Sources-LillistCore-Persistence.PersistenceController -> Packages-LillistCore-misc.CompileCoreDataModel (reads)`

## Type notes

`CompileCoreDataModel` is a compile-time SwiftPM plugin, not runtime code; it runs
in the build process, never linked into the app or CLI. `createBuildCommands` only
acts on a target it can cast to `SourceModuleTarget`
(`Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:14`),
returning `[]` otherwise. The output filename is deliberately `<name>.spm.momd`,
not `<name>.momd`, to avoid colliding with Xcode's built-in `DataModelCompile`
rule in a workspace build
(`Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:24`).
`modelInputFiles(in:)` returns an empty array on enumeration failure so the build
degrades to directory-only behaviour rather than crashing the plugin
(`Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:60`).

The manifest pins the `LillistCore` source target to StrictConcurrency and
treats all warnings as errors
(`Packages/LillistCore/Package.swift:27`); the `LillistCore` library and the
`lillist` executable are the two products
(`Packages/LillistCore/Package.swift:10`).

## External deps

- PackagePlugin — SwiftPM build-tool plugin API (`BuildToolPlugin`, `Command`, `PluginContext`)
- swift-argument-parser — `ArgumentParser` product, dependency of the `lillist-cli` target
- xcrun / momc — Xcode's Core Data model compiler, invoked as the plugin's build command

## Gotchas

- The `.xcdatamodeld` mtime does NOT change when inner `contents` is edited, so the plugin declares each `*.xcdatamodel/contents` as an input or `momc` reuses a stale `.momd` (`Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:34`).
- The top-level `.xccurrentversion` pointer is deliberately NOT declared as an input — llbuild will not re-run `momc` on its mtime change from a plugin (`Packages/LillistCore/Plugins/CompileCoreDataModel/CompileCoreDataModel.swift:63`).
- Model entities use `codeGenerationType="manual/none"`; subclasses are hand-written under `Sources/LillistCore/ManagedObjects/`, so opening the model in Xcode must not regenerate them (`Packages/LillistCore/README.md:26`).
