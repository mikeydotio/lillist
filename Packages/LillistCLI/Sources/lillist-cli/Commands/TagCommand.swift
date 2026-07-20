import ArgumentParser
import Foundation
import LillistCore

public struct TagCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "Apply or remove tags on a task."
    )

    @Argument(help: "Task token.")
    public var token: String

    @Argument(parsing: .remaining, help: "Tag operations: +#Work, -#Home, #Inbox.")
    public var ops: [String]

    public init() {}

    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        try await CLIBridge.TagHandler.run(token: token, tokens: ops, persistence: p)
    }
}
