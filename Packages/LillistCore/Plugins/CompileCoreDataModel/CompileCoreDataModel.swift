import Foundation
import PackagePlugin

/// Build tool plugin that compiles `.xcdatamodeld` files to `.momd` using
/// Xcode's `momc` model compiler. SwiftPM does not invoke `momc` automatically
/// on Core Data resources, so this plugin closes the gap.
///
/// Each `.xcdatamodeld` resource declared on the target is compiled and
/// the resulting `.momd` directory ends up in the target's resource bundle,
/// loadable via `Bundle.module.url(forResource: "<name>", withExtension: "momd")`.
@main
struct CompileCoreDataModel: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }

        let modelDirs = sourceTarget.sourceFiles.filter { file in
            file.url.pathExtension == "xcdatamodeld"
        }

        return modelDirs.map { file in
            let inputURL = file.url
            let name = inputURL.deletingPathExtension().lastPathComponent
            // Output filename intentionally differs from `<name>.momd` so
            // the plugin's output does NOT collide with Xcode's built-in
            // `DataModelCompile` rule when this package is consumed from a
            // workspace (Xcode auto-compiles the same .xcdatamodeld into
            // `<name>.momd` and the two copy commands both target the same
            // bundle path, raising a "Multiple commands produce…" error).
            // Loaders (PersistenceController) look for `<name>.momd`
            // first, then `<name>.spm.momd` as a fallback for builds where
            // only this plugin runs (`swift test` / `swift build`).
            let outputURL = context.pluginWorkDirectoryURL.appendingPathComponent("\(name).spm.momd")

            // llbuild keys a build command on the mtime of its declared
            // `inputFiles`. The `.xcdatamodeld` is a *directory*, and its
            // mtime does NOT change when the inner `*.xcdatamodel/contents`
            // file is edited — so declaring only the directory caused a
            // stale `.momd` to be reused after a model edit (runtime
            // `NSInvalidArgumentException: must have a valid
            // NSEntityDescription`). Declare each inner `*.xcdatamodel/contents`
            // as an input so a real model edit invalidates `momc`. momc itself
            // still takes the `.xcdatamodeld` directory as its argument — it
            // needs the whole versioned bundle, not one file.
            let modelInputs = Self.modelInputFiles(in: inputURL)

            return .buildCommand(
                displayName: "Compiling Core Data model \(name)",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["momc", inputURL.path, outputURL.path],
                inputFiles: [inputURL] + modelInputs,
                outputFiles: [outputURL]
            )
        }
    }

    /// The build-relevant files *inside* an `.xcdatamodeld` bundle that must
    /// invalidate the `momc` command when edited: every
    /// `*.xcdatamodel/contents` (one per model version) — the file actually
    /// changed when you edit the model. Returns an empty array on enumeration
    /// failure so the build degrades to the previous directory-only
    /// behaviour rather than crashing the plugin.
    ///
    /// The top-level `.xccurrentversion` pointer is deliberately NOT declared.
    /// Verified empirically: neither enumerating it (a dotfile) nor declaring
    /// it by explicit path makes llbuild re-run `momc` on its mtime change
    /// from a SwiftPM build-tool plugin — so claiming to track it would be
    /// false. Harmless in practice: adding or switching a model version always
    /// edits a new `*.xcdatamodel/contents`, which IS tracked, so the version
    /// change still invalidates `momc`.
    private static func modelInputFiles(in modelBundle: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: modelBundle,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var inputs: [URL] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "contents"
                && url.deletingLastPathComponent().pathExtension == "xcdatamodel" {
                inputs.append(url)
            }
        }
        return inputs
    }
}
