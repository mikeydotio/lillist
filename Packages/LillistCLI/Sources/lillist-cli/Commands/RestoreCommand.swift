import ArgumentParser
import Foundation
import LillistCore

public struct RestoreCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "restore", abstract: "Restore a task from the Trash.")
    @Argument(help: "Task token (UUID or exact title). Use '-' to read from stdin.") public var token: String
    @Flag(name: .customLong("allow-fuzzy-from-stdin"), help: "Allow non-UUID tokens when reading from stdin.")
    public var allowFuzzy: Bool = false
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        // Pre-flight: confirm every token resolves to a trashed task before
        // restoring any (all-or-nothing). RestoreHandler.run repeats the
        // resolution against the trash list; the pre-flight throws first on a
        // bad token so partial restores can't happen.
        let trashed = try await TaskStore(persistence: p).trashed()
        for t in tokens {
            try CLIBridge.RestoreHandler.preflight(token: t, trashed: trashed)
        }
        for t in tokens {
            try await CLIBridge.RestoreHandler.run(token: t, persistence: p)
        }
    }
}
