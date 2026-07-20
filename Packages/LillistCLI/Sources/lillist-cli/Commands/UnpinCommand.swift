import ArgumentParser
import Foundation
import LillistCore

public struct UnpinCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "unpin", abstract: "Unpin a task.")
    @Argument(help: "Task token.") public var token: String
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        try await CLIBridge.PinHandler.unpin(token: token, persistence: p)
    }
}
