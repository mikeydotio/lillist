import ArgumentParser
import Foundation
import LillistCore

public struct DeleteCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "delete", abstract: "Soft-delete a task (move to Trash).")
    @Argument(help: "Task token (UUID or exact title only). Use '-' to read from stdin.") public var token: String
    @Flag(name: .customLong("allow-fuzzy-from-stdin"), help: "Allow non-UUID tokens when reading from stdin.")
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
            try await CLIBridge.DeleteHandler.run(token: t, persistence: p)
        }
    }
}
