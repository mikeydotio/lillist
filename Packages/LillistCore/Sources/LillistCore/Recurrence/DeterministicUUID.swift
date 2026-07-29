import Foundation
import CryptoKit

/// Name-based (RFC 4122 §4.3, "version 5") UUID generation.
///
/// X7: two processes (a widget and the main app on one device, or two
/// devices) can each independently spawn the "same" recurrence occurrence.
/// `NSPersistentCloudKitContainer` mints a CKRecord identity per local Core
/// Data row rather than per app-level attribute, so even a fully
/// deterministic app-level `id` doesn't prevent two rows from existing —
/// but it turns what would otherwise be two permanently-unreconcilable rows
/// (distinct random UUIDs, no signal they're "the same occurrence") into an
/// ordinary same-`id` duplicate `TaskDuplicateReconciler` (Wave 1a) already
/// knows how to find and merge. `DeterministicUUID.v5` is the building
/// block: the same `(namespace, name)` pair always yields the same `UUID`,
/// on any device, in any process, with no coordination required.
enum DeterministicUUID {
    /// Computes a version-5 UUID: SHA-1 over `namespace`'s 16 raw bytes
    /// followed by `name`'s UTF-8 bytes, with the version/variant bits set
    /// per RFC 4122 §4.3. `Insecure.SHA1` is CryptoKit's name for the
    /// algorithm — "insecure" refers to its unsuitability for security
    /// purposes (collision resistance), not to this use: SHA-1 is the
    /// literal, non-negotiable hash the UUIDv5 spec mandates for a
    /// name-based identifier, not a general-purpose cryptographic primitive
    /// here.
    static func v5(namespace: UUID, name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: Array(name.utf8))
        let digest = Array(Insecure.SHA1.hash(data: Data(bytes)))
        var uuidBytes = Array(digest.prefix(16))
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50 // version 5
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80 // variant RFC 4122
        let tuple = (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )
        return UUID(uuid: tuple)
    }
}
