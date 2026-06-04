import ArgumentParser
import Foundation
import LillistCore

public struct WatchCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Stream NDJSON events on matching task changes."
    )

    @Option(name: .long, help: "Run against a saved smart filter by name.")
    public var saved: String?

    @Option(name: .customLong("tag"), help: "Tag filter (repeatable).")
    public var tag: [String] = []

    @Option(name: .long, help: "Status filter (repeatable).")
    public var status: [String] = []

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
        try await CLIBridge.WatchHandler.run(
            flags: flags, savedFilterName: saved,
            persistence: p, now: Date(), calendar: cfg.resolvedCalendar()
        ) { event in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
                print(line)
            }
        }
    }
}
