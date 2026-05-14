import ArgumentParser
import Foundation
import LillistCore

public struct MoveCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "move", abstract: "Re-parent a task.")
    @Argument(help: "Task token. Use '-' to read tokens from stdin.") public var token: String
    @Argument(help: "New parent token (UUID or exact title). Omit and pass --root.") public var newParent: String?
    @Flag(name: .long, help: "Move the task to the root (no parent).") public var root: Bool = false
    @Flag(name: .customLong("allow-fuzzy-from-stdin"), help: "Allow non-UUID tokens from stdin.")
    public var allowFuzzy: Bool = false
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens: [String]
        if StdinReader.isStdinSentinel(token) {
            let raw = StdinReader.readAllLines()
            tokens = allowFuzzy ? raw : (try StdinReader.validateAllUUIDs(raw))
        } else {
            tokens = [token]
        }
        for t in tokens {
            try await CLIBridge.MoveHandler.run(token: t, newParentToken: newParent, toRoot: root, persistence: p)
        }
    }
}
