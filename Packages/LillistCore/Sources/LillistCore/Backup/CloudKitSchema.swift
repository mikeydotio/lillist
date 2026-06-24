import Foundation

/// The integer CloudKit schema version stamped on every `LillistTask` record
/// (issue #7) and serialized into every per-task backup file.
///
/// This is **distinct** from the two other version constants in the codebase —
/// keeping them separate is deliberate, never conflate them:
///
/// - ``ExportSchema/version`` — the JSON *document* DTO contract used by the
///   full-bundle `Exporter`/`Importer`.
/// - ``BackupPackageSchema/version`` — the on-disk *directory/file layout* of
///   the live backup package.
/// - `CloudKitSchema.currentVersion` (this) — the *CloudKit record* shape, i.e.
///   the schema generation a task record conforms to. It is the gate the
///   restore flow checks: a backup may only be restored when the version baked
///   into its files matches the version this build understands.
///
/// Bump `currentVersion` only when the `LillistTask` CloudKit record shape
/// changes in a way that affects backup/restore compatibility.
public enum CloudKitSchema {
    /// The schema version this build writes and understands.
    public static let currentVersion: Int = 1
}
