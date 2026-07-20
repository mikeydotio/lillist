import ArgumentParser
import Foundation
import LillistCore

/// Root command for the `lillist` CLI.
///
/// `@main` was removed in Task 24 — `main.swift` calls
/// `Lillist.runWithExitCodes()` instead, so `LillistError` thrown inside any
/// subcommand maps to the design Section 6 exit codes (3/4/5/2/1).
public struct Lillist: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "lillist",
        abstract: "Lillist — task management from the command line.",
        version: LillistCoreInfo.version,
        subcommands: [
            AddCommand.self, LsCommand.self, ShowCommand.self, EditCommand.self,
            StatusCommand.self, NoteCommand.self,
            TagCommand.self, PinCommand.self, UnpinCommand.self,
            MoveCommand.self, DeleteCommand.self, RestoreCommand.self, PurgeCommand.self,
            AttachCommand.self, LinkCommand.self, NudgeCommand.self,
            TagsCommand.self, FiltersCommand.self,
            SearchCommand.self, CountCommand.self, EvalCommand.self,
            ExportCommand.self, VersionCommand.self, CompletionCommand.self,
            WatchCommand.self, ReportCrashCommand.self
        ],
        defaultSubcommand: nil
    )

    public init() {}
}

extension Lillist {
    /// Custom main that maps thrown `LillistError`s onto the design Section 6
    /// exit codes. Argument-parser parse errors continue to exit 2 via its
    /// built-in handling (`exit(withError:)`).
    public static func runWithExitCodes() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            Foundation.exit(ExitCode.success)
        } catch let lillist as LillistError {
            FileHandle.standardError.write(Data((lillist.localizedDescription + "\n").utf8))
            Foundation.exit(ExitCode.fromLillistError(lillist))
        } catch {
            // Argument-parser parse errors / CleanExit / ExitCode flow through
            // its built-in renderer.
            Lillist.exit(withError: error)
        }
    }
}
