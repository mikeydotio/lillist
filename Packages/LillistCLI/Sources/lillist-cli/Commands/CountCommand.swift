import ArgumentParser
import Foundation
import LillistCore

public struct CountCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(commandName: "count", abstract: "Print the count of matching tasks (single integer).")
    @Option(name: .long) public var saved: String?
    @Option(name: .customLong("tag")) public var tag: [String] = []
    @Option(name: .long) public var status: [String] = []
    @Flag(name: .customLong("include-trash")) public var includeTrash: Bool = false
    public init() {}
    public func run() async throws {
        let p = try await CLIBridge.StoreLocator.openAppGroup()
        let cfg = try CLIBridge.Config.read(from: CLIBridge.Config.defaultLocation())
        var flags = CLIBridge.FilterFlags()
        flags.tags = tag
        flags.statuses = try status.map {
            guard let s = CLIBridge.AddHandler.status(from: $0) else {
                throw LillistError.validationFailed([.init(field: "status", message: "unknown '\($0)'")])
            }
            return s
        }
        flags.includeTrash = includeTrash
        let n = try await CLIBridge.CountHandler.run(
            flags: flags, savedFilterName: saved, persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        )
        print(n)
    }
}
