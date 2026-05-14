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
        subcommands: [AddCommand.self, LsCommand.self, ShowCommand.self, EditCommand.self],
        defaultSubcommand: nil
    )

    public init() {}
}
