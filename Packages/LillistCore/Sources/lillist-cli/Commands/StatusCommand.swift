import ArgumentParser
import Foundation
import LillistCore

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Transition a task's status."
    )

    @Argument(help: "Task token.")
    public var token: String

    @Argument(help: "Target status: todo|started|blocked|closed.")
    public var newStatus: String

    @Option(name: .long, help: "Optional note appended after the transition.")
    public var note: String?

    @OptionGroup public var globals: GlobalOptions

    public init() {}

    public func run() async throws {
        guard let s = CLIBridge.AddHandler.status(from: newStatus) else {
            throw LillistError.validationFailed([.init(field: "status", message: "unknown '\(newStatus)'")])
        }
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        try await CLIBridge.StatusHandler.run(token: token, to: s, note: note, persistence: p)
    }
}
