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
            throw Error.schemaInitializationFailed((error as NSError).localizedDescription)
        }
        #else
        // Release builds rely on the manually-promoted production schema.
        return
        #endif
    }
}
