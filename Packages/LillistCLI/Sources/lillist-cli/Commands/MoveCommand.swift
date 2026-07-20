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
        let tokens = try BatchTokens.resolveInput(
            token: token,
            destructiveGate: .requireUUIDs,
            allowFuzzy: allowFuzzy
        )
        let newParentID: UUID?
        if root {
            newParentID = nil
        } else if let pt = newParent {
            let pr = try await CLIBridge.Resolver.resolve(
                token: pt, scope: .anywhereIncludingClosed,
                destructiveness: .destructive, persistence: p
            )
            newParentID = pr.id
        } else {
            throw LillistError.validationFailed([
                .init(field: "parent", message: "must specify a new parent or --root")
            ])
        }
        let resolutions = try await CLIBridge.Resolver.resolveAll(
            tokens: tokens,
            scope: .anywhereIncludingClosed,
            destructiveness: .destructive,
            persistence: p
        )
        let store = TaskStore(persistence: p)
        for r in resolutions {
            try await store.reparent(id: r.id, newParent: newParentID)
        }
    }
}
