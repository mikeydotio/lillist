import Foundation

/// Sample-preview text shown in the Preferences "View what would be
/// sent" disclosure. Plan 9 ships the post-crash prompt; Plan 14
/// consolidates the two app-target preview builders that had drifted.
public enum CrashReportSample {
    public struct Environment: Sendable, Equatable {
        public var buildVersion: String
        public var osVersion: String
        public var deviceModel: String
        public var recipient: String
        public var methodSuffix: String

        public init(
            buildVersion: String,
            osVersion: String,
            deviceModel: String,
            recipient: String,
            methodSuffix: String
        ) {
            self.buildVersion = buildVersion
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.recipient = recipient
            self.methodSuffix = methodSuffix
        }
    }

    /// Render the multi-line preview string. macOS callers pass
    /// `methodSuffix: "macOS Mail.app draft via mailto: — you choose
    /// whether to send."`; iOS uses `"Mail (you choose whether to
    /// send.)"`.
    public static func preview(_ env: Environment) -> String {
        """
        Build: \(env.buildVersion)
        OS: \(env.osVersion)
        Device: \(env.deviceModel)
        Sent to: \(env.recipient)
        Method: \(env.methodSuffix)
        """
    }
}
