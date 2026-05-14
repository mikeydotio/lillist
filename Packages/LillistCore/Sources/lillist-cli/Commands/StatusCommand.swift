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
        let tokens: [String]
        if StdinReader.isStdinSentinel(token) {
            let raw = StdinReader.readAllLines()
            // Closed-transition is destructive; require UUIDs unless allowed.
            if s == .closed && allowFuzzy == false {
                tokens = try StdinReader.validateAllUUIDs(raw)
            } else {
                tokens = raw
            }
        } else {
            tokens = [token]
        }
        for t in tokens {
            try await CLIBridge.StatusHandler.run(token: t, to: s, note: note, persistence: p)
        }
    }
}
