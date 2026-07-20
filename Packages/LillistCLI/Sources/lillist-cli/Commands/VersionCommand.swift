import ArgumentParser
import Foundation
import LillistCore

public struct VersionCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "version", abstract: "Print the CLI version.")
    public init() {}
    public func run() throws {
        print("lillist \(LillistCoreInfo.version)")
    }
}
