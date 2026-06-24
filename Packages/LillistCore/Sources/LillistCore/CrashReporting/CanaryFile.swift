import Foundation

/// Manages the on-disk presence of the launch canary.
///
/// Design Section 8: written on clean launch, deleted on clean
/// termination, presence on the next launch implies a crash.
public struct CanaryFile: Sendable {
    /// Logical owner of the canary; controls which path is used by
    /// `defaultURL(for:)`.
    public enum Platform: Sendable {
        case macOSApp
        case macOSCLI
        case iOSApp
    }

    public let url: URL

    /// Direct-URL initializer; primarily for tests but also used by
    /// callers that have already resolved an app-group container URL.
    public init(url: URL) {
        self.url = url
    }

    /// Standard path resolution per design Section 8.
    ///
    /// macOS: `~/Library/Application Support/Lillist/launch.canary`
    /// macOS CLI: `~/Library/Application Support/Lillist/launch-cli.canary`
    /// iOS: app-group container `group.app.lillist/launch.canary`
    public static func defaultURL(for platform: Platform) -> URL {
        switch platform {
        case .macOSApp:
            return appSupportLillist().appendingPathComponent("launch.canary")
        case .macOSCLI:
            return appSupportLillist().appendingPathComponent("launch-cli.canary")
        case .iOSApp:
            let groupID = "group.app.lillist"
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: groupID)
                ?? FileManager.default.temporaryDirectory
            return container.appendingPathComponent("launch.canary")
        }
    }

    private static func appSupportLillist() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("Lillist", isDirectory: true)
    }

    /// Atomically replace the canary contents with the given record.
    public func writeFresh(_ canary: CrashCanary) throws {
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(canary)
        try data.write(to: url, options: .atomic)
    }

    /// Read the canary if it exists. Returns nil for missing or
    /// corrupt files; corrupt files are deleted so a poisoned write
    /// doesn't haunt the user forever.
    public func readIfPresent() throws -> CrashCanary? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(CrashCanary.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Remove the canary; safe to call when the file does not exist.
    public func deleteOnCleanExit() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
