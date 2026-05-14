import ArgumentParser
import Foundation
import LillistCore

/// Root command for the `lillist` CLI. Subcommands are added in subsequent tasks.
@main
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
            TagsCommand.self
        ],
        defaultSubcommand: nil
    )

    public init() {}
}
