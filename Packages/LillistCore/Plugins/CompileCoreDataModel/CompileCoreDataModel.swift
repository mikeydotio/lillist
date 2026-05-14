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
            return .buildCommand(
                displayName: "Compiling Core Data model \(name)",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["momc", inputURL.path, outputURL.path],
                inputFiles: [inputURL],
                outputFiles: [outputURL]
            )
        }
    }
}
