import ArgumentParser
import Foundation
import LillistCore

public struct SearchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "search", abstract: "Full-text search across tasks.")
    @Argument(help: "Search query.") public var query: String
    @Option(name: .long, help: "Restrict to descendants of this task.") public var scope: String?
    @OptionGroup public var globals: GlobalOptions
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let records = try await CLIBridge.SearchHandler.run(query: query, scopeToken: scope, persistence: p)
        switch globals.resolveOutputFormat(default: .pretty) {
        case .json: print(try CLIBridge.TaskRenderer.jsonString(records))
        case .ndjson: print(try CLIBridge.TaskRenderer.ndjson(records), terminator: "")
        case .tsv: print(try CLIBridge.TaskRenderer.tsv(records), terminator: "")
        case .pretty: print(CLIBridge.TaskRenderer.prettyTree(records, color: globals.resolveColor()), terminator: "")
        }
    }
}
