import ArgumentParser
import Foundation
import LillistCore

public struct MoveCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "move", abstract: "Re-parent a task.")
    @Argument(help: "Task token.") public var token: String
    @Argument(help: "New parent token (UUID or exact title). Omit and pass --root.") public var newParent: String?
    @Flag(name: .long, help: "Move the task to the root (no parent).") public var root: Bool = false
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        try await CLIBridge.MoveHandler.run(token: token, newParentToken: newParent, toRoot: root, persistence: p)
    }
}
