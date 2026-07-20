import ArgumentParser
import Foundation
import LillistCore

public struct PinCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "pin", abstract: "Pin a task.")
    @Argument(help: "Task token.") public var token: String
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        try await CLIBridge.PinHandler.pin(token: token, persistence: p)
    }
}
