import ArgumentParser
import Foundation
import LillistCore

public struct AttachCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "attach", abstract: "Attach one or more files to a task.")
    @Argument(help: "Task token.") public var token: String
    @Argument(parsing: .remaining, help: "Paths to attach.") public var paths: [String]
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let ids = try await CLIBridge.AttachHandler.run(token: token, paths: paths, persistence: p)
        for id in ids { print(id.uuidString) }
    }
}
