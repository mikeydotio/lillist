import ArgumentParser
import Foundation
import LillistCore

public struct ExportCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "export", abstract: "Export all data (JSON + assets folder).")
    @Argument(help: "Target directory (must be empty or non-existent).") public var dir: String
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let url = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        try await CLIBridge.ExportHandler.run(directory: url, persistence: p)
        print("Exported to \(url.path)")
    }
}
