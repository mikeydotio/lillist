import ArgumentParser
import Foundation
import LillistCore

public struct ReportCrashCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "report-crash",
        abstract: "Send a redacted crash report by email."
    )

    @Flag(name: .long, help: "Skip the logs section.")
    public var noLogs: Bool = false

    @Flag(name: .long, help: "Skip the breadcrumbs section.")
    public var noBreadcrumbs: Bool = false

    public init() {}

    public func run() async throws {
        // Re-detect — main.swift may have already consumed the stale
        // canary on startup, in which case there's nothing to send.
        let canaryFile = CanaryFile(url: CanaryFile.defaultURL(for: .macOSCLI))
        guard let pending = try canaryFile.readIfPresent() else {
            FileHandle.standardError.write(Data("No pending crash to report.\n".utf8))
            return
        }

        let reporter = CrashReporter(
            canaryFile: canaryFile,
            buildVersion: LillistCoreInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Host.current().localizedName ?? "Mac",
            hostname: Host.current().localizedName ?? "Mac",
            logFetcher: OSLogFetcher(),
            breadcrumbs: BreadcrumbBuffer(),
            transport: CLIMailtoTransport()
        )

        // Print the redacted payload first so the user can see what
        // they're agreeing to send.
        let preview = CrashReport(
            buildVersion: LillistCoreInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Host.current().localizedName ?? "Mac",
            canary: pending,
            userDescription: nil,
            logs: noLogs ? nil : ["(logs will be loaded and redacted when sent)"],
            breadcrumbs: noBreadcrumbs ? nil : []
        )
        print(preview.renderedAsPlainText())

        // Read description from stdin (single line).
        FileHandle.standardError.write(Data("Describe what you were doing (Enter to skip): ".utf8))
        let description = readLine()

        try await reporter.submit(
            decision: .send,
            description: description,
            includeLogs: !noLogs,
            includeBreadcrumbs: !noBreadcrumbs,
            pending: pending
        )
    }
}
