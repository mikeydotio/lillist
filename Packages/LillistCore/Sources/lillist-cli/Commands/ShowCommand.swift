import ArgumentParser
import Foundation
import LillistCore

public struct ShowCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show full detail for a single task."
    )

    @Argument(help: "Task UUID, UUID prefix, or fuzzy title token. Use '-' to read from stdin.")
    public var token: String

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens: [String] = StdinReader.isStdinSentinel(token)
            ? StdinReader.readAllLines()
            : [token]
        for t in tokens {
            try await renderOne(token: t, persistence: p)
        }
    }

    private func renderOne(token: String, persistence: PersistenceController) async throws {
        let result = try await CLIBridge.ShowHandler.run(token: token, persistence: persistence)

        if result.pickedSilently {
            FileHandle.standardError.write(Data("note: '\(token)' partially matched '\(result.task.title)'\n".utf8))
        }

        let format = globals.resolveOutputFormat(default: .pretty)
        switch format {
        case .json:
            let data = try CLIBridge.TaskRenderer.json([result.task])
            print(String(data: data, encoding: .utf8) ?? "")
        case .ndjson:
            print(try CLIBridge.TaskRenderer.ndjson([result.task]), terminator: "")
        case .tsv:
            print(try CLIBridge.TaskRenderer.tsv([result.task]), terminator: "")
        case .pretty:
            print(CLIBridge.TaskRenderer.prettyTree([result.task], color: globals.resolveColor()), terminator: "")
            if result.journal.isEmpty == false {
                print("\nJournal:")
                print(CLIBridge.JournalRenderer.prettyList(result.journal, color: globals.resolveColor()), terminator: "")
            }
        }
    }
}
