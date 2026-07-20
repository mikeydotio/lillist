import ArgumentParser
import Foundation
import LillistCore
import LillistSearchIntelligence

public struct SearchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "search", abstract: "Full-text search across tasks.")
    @Argument(help: "Search query.") public var query: String
    @Option(name: .long, help: "Restrict to descendants of this task.") public var scope: String?
    @Flag(name: .long, help: "Interpret the query as natural language (requires Apple Intelligence) instead of a literal substring match.")
    public var smart: Bool = false
    @OptionGroup public var globals: GlobalOptions
    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        if smart {
            try await runSmart(persistence: p)
        } else {
            let records = try await CLIBridge.SearchHandler.run(query: query, scopeToken: scope, persistence: p)
            try render(records)
        }
    }

    /// `--smart` bypasses `scope` — natural-language queries express scope
    /// as part of the query itself (there is no field for it yet), same as
    /// the plain `search` verb's scope flag has no smart-search analogue.
    private func runSmart(persistence: PersistenceController) async throws {
        guard let translator = FilterTranslatorFactory.makeBest() else {
            throw TranslationFailure.unsupported
        }
        let outcome = try await CLIBridge.AskHandler.run(query: query, persistence: persistence, translator: translator)
        if !globals.quiet {
            if let explanation = outcome.translated.explanation {
                FileHandle.standardError.write(Data("Interpreted as: \(explanation)\n".utf8))
            }
            if !outcome.translated.unmappedTerms.isEmpty {
                FileHandle.standardError.write(Data("Ignored: \(outcome.translated.unmappedTerms.joined(separator: ", "))\n".utf8))
            }
        }
        try render(outcome.records)
    }

    private func render(_ records: [TaskStore.TaskRecord]) throws {
        switch globals.resolveOutputFormat(default: .pretty) {
        case .json: print(try CLIBridge.TaskRenderer.jsonString(records))
        case .ndjson: print(try CLIBridge.TaskRenderer.ndjson(records), terminator: "")
        case .tsv: print(try CLIBridge.TaskRenderer.tsv(records), terminator: "")
        case .pretty: print(CLIBridge.TaskRenderer.prettyTree(records, color: globals.resolveColor()), terminator: "")
        }
    }
}
