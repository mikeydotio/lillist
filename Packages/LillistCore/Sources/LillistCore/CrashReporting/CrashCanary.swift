import Foundation

/// Snapshot of a process's identity at launch time.
///
/// Persisted as JSON in the canary file at launch and consulted on
/// the *next* launch to determine whether the previous run crashed.
/// See design Section 8.
public struct CrashCanary: Codable, Equatable, Sendable {
    /// The OS process ID of the run.
    public let pid: Int32
    /// When the process began. Used to bound the OSLog query window
    /// on the next launch.
    public let startedAt: Date
    /// Marketing version + build number (e.g. `"1.0.0 (123)"`).
    public let buildVersion: String
    /// Device hostname. Useful for differentiating a Mac crash from
    /// an iPhone crash when Mikey triages a report.
    public let hostname: String

    public init(pid: Int32, startedAt: Date, buildVersion: String, hostname: String) {
        self.pid = pid
        self.startedAt = startedAt
        self.buildVersion = buildVersion
        self.hostname = hostname
    }
}
