import ArgumentParser
import Foundation
import LillistCore

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Transition a task's status."
    )

    @Argument(help: "Task token. Use '-' to read tokens from stdin.")
    public var token: String

    @Argument(help: "Target status: todo|started|blocked|closed.")
    public var newStatus: String

    @Option(name: .long, help: "Optional note appended after the transition.")
    public var note: String?

    @Flag(name: .customLong("allow-fuzzy-from-stdin"),
          help: "When transitioning to closed, allow non-UUID tokens from stdin.")
    public var allowFuzzy: Bool = false

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        guard let s = CLIBridge.AddHandler.status(from: newStatus) else {
            throw LillistError.validationFailed([.init(field: "status", message: "unknown '\(newStatus)'")])
        }
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let destructive = (s == .closed)
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: destructive ? .requireUUIDs : .none,
            allowFuzzy: allowFuzzy
        )
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: destructive ? .destructive : .readOnly,
            persistence: p
        )
        let tasks = TaskStore(persistence: p)
        let journal = JournalStore(persistence: p)
        for r in resolutions {
            try await tasks.transition(id: r.id, to: s)
            if let body = note, body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                _ = try await journal.appendNote(taskID: r.id, body: body)
            }
        }
    }
}
