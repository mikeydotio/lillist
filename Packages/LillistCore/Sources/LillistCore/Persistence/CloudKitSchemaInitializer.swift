import Foundation
import CoreData

/// DEBUG-only bootstrapping of the CloudKit development schema from the
/// Core Data model (design Section 3).
///
/// `NSPersistentCloudKitContainer.initializeCloudKitSchema(options:)`
/// inspects the Core Data model and creates/updates the matching record
/// types in CloudKit's development environment. It must never run in
/// production — promotion to the production schema is a manual step
/// performed via CloudKit Dashboard.
///
/// Callers (the host app's launch sequence, added in a later plan) wire
/// this in behind `#if DEBUG`. The `dryRun` flag lets tests verify the
/// invocation contract without actually contacting CloudKit.
public enum CloudKitSchemaInitializer {
    public enum Error: Swift.Error { case schemaInitializationFailed(String) }

    /// Initialize the CloudKit development schema if we're in a DEBUG build.
    /// - Parameters:
    ///   - persistence: the controller whose container will be initialized.
    ///   - dryRun: if true, skip the real CloudKit call and only invoke the `onInvoke` callback.
    ///   - onInvoke: test hook to confirm the initializer was entered.
    public static func initializeIfNeeded(
        persistence: PersistenceController,
        dryRun: Bool = false,
        onInvoke: (() -> Void)? = nil
    ) throws {
        onInvoke?()
        guard !dryRun else { return }
        #if DEBUG
        guard let ckContainer = persistence.container as? NSPersistentCloudKitContainer else {
            // In-memory test/preview controllers use plain NSPersistentContainer
            // (see PersistenceController.makeContainer) and have nothing to
            // bootstrap against CloudKit. Bail out silently.
            return
        }
        do {
            try ckContainer.initializeCloudKitSchema(options: [])
        } catch {
            throw Error.schemaInitializationFailed(Self.describe(error))
        }
        #else
        // Release builds rely on the manually-promoted production schema.
        return
        #endif
    }

    /// Flatten an `NSError` into something a human can act on.
    ///
    /// `localizedDescription` for a Core Data failure is the notoriously
    /// content-free "A Core Data error occurred." Everything that identifies
    /// *which* rule the model broke lives in `userInfo` — `NSUnderlyingError`,
    /// and for validation failures a `NSDetailedErrors` array with one entry
    /// per offending entity/property. Reporting only the localized string
    /// discards exactly the part worth reading.
    static func describe(_ error: Swift.Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain) \(ns.code): \(ns.localizedDescription)"]

        if let detailed = ns.userInfo[NSDetailedErrorsKey] as? [NSError] {
            for sub in detailed.prefix(20) {
                parts.append("  ↳ \(sub.domain) \(sub.code): \(sub.localizedDescription)")
                for (key, value) in sub.userInfo where key != NSUnderlyingErrorKey {
                    parts.append("      \(key) = \(value)")
                }
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("  ↳ underlying: \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
            for (key, value) in underlying.userInfo where key != NSUnderlyingErrorKey {
                parts.append("      \(key) = \(value)")
            }
        }
        for (key, value) in ns.userInfo
        where key != NSDetailedErrorsKey && key != NSUnderlyingErrorKey {
            parts.append("  \(key) = \(value)")
        }
        return parts.joined(separator: "\n")
    }
}
