import Foundation
import CoreData

public final class AttachmentStore: @unchecked Sendable {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.container.viewContext }

    /// Files larger than this byte count are rejected outright.
    public static let hardSizeLimit: Int64 = 500 * 1024 * 1024

    /// Optional breadcrumb sink. See Plan 9 / design Section 8.
    public var breadcrumbs: BreadcrumbBuffer?

    fileprivate func recordCrumb(_ action: String, success: Bool) async {
        if let b = breadcrumbs {
            try? await b.record(action: action, success: success)
        }
    }

    public init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    public struct AttachmentRecord: Sendable, Equatable {
        public var id: UUID
        public var taskID: UUID
        public var journalEntryID: UUID?
        public var kind: AttachmentKind
        public var filename: String
        public var uti: String
        public var byteSize: Int64
        public var hasData: Bool
        public var linkPreviewJSON: String?
        public var createdAt: Date?
    }

    public struct LinkPreviewPayload: Codable, Sendable {
        public var url: String
        public var title: String?
        public var description: String?
        public var fetchedAt: Date
    }

    // MARK: - Add image

    @discardableResult
    public func addImage(taskID: UUID, filename: String, data: Data) async throws -> UUID {
        try checkSize(byteCount: Int64(data.count))
        return try await insertAttachment(
            taskID: taskID,
            kind: .image,
            filename: filename,
            uti: "public.image",
            data: data,
            linkPreviewJSON: nil
        )
    }

    // MARK: - Add file

    @discardableResult
    public func addFile(taskID: UUID, filename: String, uti: String, data: Data) async throws -> UUID {
        try checkSize(byteCount: Int64(data.count))
        return try await insertAttachment(
            taskID: taskID,
            kind: .file,
            filename: filename,
            uti: uti,
            data: data,
            linkPreviewJSON: nil
        )
    }

    // MARK: - Add link preview

    @discardableResult
    public func addLinkPreview(
        taskID: UUID,
        url: URL,
        title: String?,
        description: String?,
        thumbnailData: Data?,
        faviconData: Data?
    ) async throws -> UUID {
        _ = thumbnailData; _ = faviconData
        let payload = LinkPreviewPayload(
            url: url.absoluteString,
            title: title,
            description: description,
            fetchedAt: Date()
        )
        let json = try String(data: JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        return try await insertAttachment(
            taskID: taskID,
            kind: .linkPreview,
            filename: url.absoluteString,
            uti: "public.url",
            data: nil,
            linkPreviewJSON: json
        )
    }

    // MARK: - Update link preview

    /// Replace the unfurled metadata for an existing link-preview
    /// attachment. Called by `LinkPreviewUnfurler` once it has fetched
    /// OG/Twitter card data (and optionally a thumbnail). Pass
    /// `LinkPreviewMetadata.empty` to update only the thumbnail bytes.
    public func updateLinkPreview(
        id: UUID,
        metadata: LinkPreviewMetadata,
        thumbnailData: Data? = nil
    ) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            guard m.kindRaw == Int16(AttachmentKind.linkPreview.rawValue) else {
                throw LillistError.validationFailed([
                    .init(field: "kind", message: "attachment is not a link preview")
                ])
            }

            // Merge: keep existing fields if metadata fields are nil.
            var existing: LinkPreviewPayload?
            if let json = m.linkPreviewJSON, let bytes = json.data(using: .utf8) {
                existing = try? JSONDecoder().decode(LinkPreviewPayload.self, from: bytes)
            }
            let merged = LinkPreviewPayload(
                url: existing?.url ?? "",
                title: metadata.title ?? existing?.title,
                description: metadata.description ?? existing?.description,
                fetchedAt: Date()
            )
            let encoded = try JSONEncoder().encode(merged)
            m.linkPreviewJSON = String(data: encoded, encoding: .utf8)

            if let bytes = thumbnailData {
                m.data = bytes
                m.byteSize = Int64(bytes.count)
            }
            try context.save()
        }
    }

    // MARK: - Read

    public func fetch(id: UUID) async throws -> AttachmentRecord {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            return Self.record(from: m)
        }
    }

    /// Explicitly request the binary bytes for an attachment.
    ///
    /// CloudKit auto-downloads small assets, but larger ones may need an
    /// explicit fetch on iOS/iPadOS (design Section 3 — "lazy download.
    /// Metadata available immediately; bytes load on first access").
    /// Accessing `.data` triggers `NSPersistentCloudKitContainer`'s asset
    /// materialization for any pending download.
    ///
    /// - Throws: `LillistError.notFound` if the attachment row doesn't exist.
    /// - Throws: `LillistError.attachmentFetchFailed` if the row exists but
    ///   has no data bytes (e.g. a link-preview row, or a CKAsset that
    ///   couldn't be downloaded).
    public func downloadData(id: UUID) async throws -> Data {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            // Touching `m.data` is what causes the asset materialization.
            guard let bytes = m.data else {
                let sentinelURL = URL(string: "lillist://attachment/\(id.uuidString)")!
                throw LillistError.attachmentFetchFailed(url: sentinelURL)
            }
            return bytes
        }
    }

    public func attachments(forTask taskID: UUID) async throws -> [AttachmentRecord] {
        try await context.perform { [self] in
            let req = NSFetchRequest<Attachment>(entityName: "Attachment")
            req.predicate = NSPredicate(format: "task.id == %@", taskID as CVarArg)
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            return try context.fetch(req).map(Self.record(from:))
        }
    }

    // MARK: - Delete

    public func delete(id: UUID) async throws {
        try await context.perform { [self] in
            let m = try fetchManagedObject(id: id, in: context)
            context.delete(m)
            try context.save()
        }
    }

    // MARK: - Helpers

    private func checkSize(byteCount: Int64) throws {
        if byteCount > Self.hardSizeLimit {
            throw LillistError.attachmentTooLarge(byteSize: byteCount)
        }
    }

    private func insertAttachment(
        taskID: UUID,
        kind: AttachmentKind,
        filename: String,
        uti: String,
        data: Data?,
        linkPreviewJSON: String?
    ) async throws -> UUID {
        do {
            let id: UUID = try await context.perform { [self] in
                let task = try fetchTask(id: taskID, in: context)
                let journal = JournalEntry(context: context)
                journal.id = UUID()
                journal.task = task
                journal.kind = .attachment
                journal.createdAt = Date()
                journal.body = ""

                let att = Attachment(context: context)
                att.id = UUID()
                att.task = task
                att.journalEntry = journal
                att.kind = kind
                att.filename = filename
                att.uti = uti
                att.byteSize = Int64(data?.count ?? 0)
                att.data = data
                att.linkPreviewJSON = linkPreviewJSON
                att.createdAt = journal.createdAt

                try context.save()
                return att.id!
            }
            await recordCrumb("attachment.attach", success: true)
            return id
        } catch {
            await recordCrumb("attachment.attach", success: false)
            throw error
        }
    }

    private func fetchManagedObject(id: UUID, in ctx: NSManagedObjectContext) throws -> Attachment {
        let req = NSFetchRequest<Attachment>(entityName: "Attachment")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    private func fetchTask(id: UUID, in ctx: NSManagedObjectContext) throws -> LillistTask {
        let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
        return m
    }

    static func record(from m: Attachment) -> AttachmentRecord {
        AttachmentRecord(
            id: m.id ?? UUID(),
            taskID: m.task?.id ?? UUID(),
            journalEntryID: m.journalEntry?.id,
            kind: m.kind,
            filename: m.filename ?? "",
            uti: m.uti ?? "",
            byteSize: m.byteSize,
            hasData: m.data != nil,
            linkPreviewJSON: m.linkPreviewJSON,
            createdAt: m.createdAt
        )
    }
}
