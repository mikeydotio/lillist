import Foundation

/// User-facing crash report bundle.
///
/// Composition is opt-in section by section per design Section 8:
/// `logs` is nil unless the user kept the "Recent app logs" checkbox
/// on; `breadcrumbs` is nil unless they kept the breadcrumbs checkbox
/// on. `userDescription` may be nil if they didn't type anything.
public struct CrashReport: Codable, Equatable, Sendable {
    public let buildVersion: String
    public let osVersion: String
    public let deviceModel: String
    public let canary: CrashCanary
    public let userDescription: String?
    public let logs: [String]?
    public let breadcrumbs: [Breadcrumb]?

    public init(
        buildVersion: String,
        osVersion: String,
        deviceModel: String,
        canary: CrashCanary,
        userDescription: String?,
        logs: [String]?,
        breadcrumbs: [Breadcrumb]?
    ) {
        self.buildVersion = buildVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.canary = canary
        self.userDescription = userDescription
        self.logs = logs
        self.breadcrumbs = breadcrumbs
    }

    /// Human-readable text rendering suitable for a mailto body or
    /// a `.lillistcrash` bundle's primary file. Stable across runs.
    public func renderedAsPlainText() -> String {
        var lines: [String] = []
        lines.append("Lillist crash report")
        lines.append("====================")
        lines.append("")
        lines.append("Build: \(buildVersion)")
        lines.append("OS: \(osVersion)")
        lines.append("Device: \(deviceModel)")
        lines.append("Host: \(canary.hostname)")
        lines.append("PID: \(canary.pid)")
        lines.append("Started: \(ISO8601DateFormatter().string(from: canary.startedAt))")
        lines.append("")
        if let userDescription, !userDescription.isEmpty {
            lines.append("--- What I was doing ---")
            lines.append(userDescription)
            lines.append("")
        }
        if let logs {
            lines.append("--- Logs (\(logs.count) lines, redacted) ---")
            lines.append(contentsOf: logs)
            lines.append("")
        }
        if let breadcrumbs {
            lines.append("--- Breadcrumbs (\(breadcrumbs.count)) ---")
            for crumb in breadcrumbs {
                let outcome = crumb.success ? "ok" : "fail"
                let at = ISO8601DateFormatter().string(from: crumb.at)
                lines.append("\(at) \(crumb.action) \(outcome)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
