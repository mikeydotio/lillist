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
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        // Pre-resolve all tokens so a single bad token aborts before any
        // mutation (all-or-nothing).
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.softDelete(id: r.id)
        }
    }
}
