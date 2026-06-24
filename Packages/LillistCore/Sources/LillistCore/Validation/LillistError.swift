import Foundation

/// Single error type for all `LillistCore` public APIs.
public enum LillistError: Error, Sendable, Equatable {
    public struct Issue: Sendable, Equatable {
        public let field: String
        public let message: String
        public init(field: String, message: String) {
            self.field = field
            self.message = message
        }
    }

    case storeUnavailable(reason: String)
    case iCloudUnavailable(reason: String)
    case syncFailure(underlying: String)
    case validationFailed([Issue])
    case notFound
    case ambiguous([UUID])
    case quotaExceeded(resource: String)
    case attachmentTooLarge(byteSize: Int64)
    case attachmentFetchFailed(url: URL)
    /// Plan 21 recovery: a destructive store operation needs more free
    /// disk space than the volume can provide. Carries both figures so
    /// the recovery UI can tell the user exactly how short they are.
    case insufficientDiskSpace(neededBytes: Int64, availableBytes: Int64)
    case migrationRequired
    case migrationFailed(underlying: String)
    case modelUnavailable(searchedFilenames: [String])
    case unsupportedExportVersion(found: Int, supported: Int)
    /// A backup archive's CloudKit schema version does not match this build's
    /// current version, so it cannot be safely restored (issue #7).
    case schemaVersionMismatch(found: Int, current: Int)
}

extension LillistError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .storeUnavailable(let reason):
            return "The Lillist data store is unavailable: \(reason)"
        case .iCloudUnavailable(let reason):
            return "iCloud is unavailable: \(reason)"
        case .syncFailure(let underlying):
            return "Sync failed: \(underlying)"
        case .validationFailed(let issues):
            let parts = issues.map { "\($0.field): \($0.message)" }
            return "Validation failed: \(parts.joined(separator: "; "))"
        case .notFound:
            return "The requested item could not be found."
        case .ambiguous(let ids):
            return "Multiple matching items (\(ids.count)). Please be more specific."
        case .quotaExceeded(let resource):
            return "Storage quota exceeded for \(resource)."
        case .attachmentTooLarge(let byteSize):
            return "Attachment is too large (\(byteSize) bytes)."
        case .attachmentFetchFailed(let url):
            return "Could not fetch attachment from \(url.absoluteString)."
        case .insufficientDiskSpace(let neededBytes, let availableBytes):
            return "Not enough free disk space to safely back up the data store: \(neededBytes) bytes needed, \(availableBytes) bytes available."
        case .migrationRequired:
            return "A data migration is required to open this store."
        case .migrationFailed(let underlying):
            return "Data migration failed: \(underlying)"
        case .modelUnavailable(let names):
            return "Lillist data model not found in app bundle (searched: \(names.joined(separator: ", ")))"
        case .unsupportedExportVersion(let found, let supported):
            return "This export was written by a newer version of Lillist (schema \(found); this app supports up to \(supported)). Update Lillist and try again."
        case .schemaVersionMismatch(let found, let current):
            return "This backup was made with a different data schema (version \(found); this app uses \(current)) and can't be restored."
        }
    }
}
