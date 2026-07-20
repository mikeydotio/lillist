import ArgumentParser
import Foundation
import LillistCore

public struct EvalCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "eval", abstract: "Evaluate a PredicateGroup JSON expression against the task set.")
    @Argument(help: "Predicate group as a JSON string, or '-' to read from stdin.") public var expression: String
    @OptionGroup public var globals: GlobalOptions
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())
        let json: String
        if StdinReader.isStdinSentinel(expression) {
            json = StdinReader.readAllLines().joined(separator: "\n")
        } else {
            json = expression
        }
        let records = try await CLIBridge.EvalHandler.run(
            groupJSON: json, persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        )
        switch globals.resolveOutputFormat(default: .ndjson) {
        case .json: print(try CLIBridge.TaskRenderer.jsonString(records))
        case .ndjson: print(try CLIBridge.TaskRenderer.ndjson(records), terminator: "")
        case .tsv: print(try CLIBridge.TaskRenderer.tsv(records), terminator: "")
        case .pretty: print(CLIBridge.TaskRenderer.prettyTree(records, color: globals.resolveColor()), terminator: "")
        }
    }
}
