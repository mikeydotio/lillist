import ArgumentParser
import Foundation
import LillistCore

public struct LinkCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "link", abstract: "Attach a URL (link preview) to a task.")
    @Argument(help: "Task token.") public var token: String
    @Argument(help: "URL to attach.") public var url: String
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let id = try await CLIBridge.LinkHandler.run(token: token, urlString: url, persistence: p)
        print(id.uuidString)
    }
}
