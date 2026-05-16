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
    case migrationRequired
    case migrationFailed(underlying: String)
    case modelUnavailable(searchedFilenames: [String])
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
        case .migrationRequired:
            return "A data migration is required to open this store."
        case .migrationFailed(let underlying):
            return "Data migration failed: \(underlying)"
        case .modelUnavailable(let names):
            return "Lillist data model not found in app bundle (searched: \(names.joined(separator: ", ")))"
        }
    }
}
