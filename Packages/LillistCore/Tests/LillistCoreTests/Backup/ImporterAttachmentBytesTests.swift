import Testing
import Foundation
import CoreData
@testable import LillistCore

/// Wave 4 — the `Importer` attachment-bytes extension (issue #7 full restore).
@Suite("Importer attachment bytes")
struct ImporterAttachmentBytesTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-attbytes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func taskDTO(id: UUID) -> ExportSchema.TaskDTO {
        ExportSchema.TaskDTO(
            id: id, title: "Owner", notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1, isPinned: false, parentID: nil, tagIDs: [],
            createdAt: Date(), modifiedAt: Date(), closedAt: nil, deletedAt: nil
        )
    }

    private func prefsDTO() -> ExportSchema.PreferencesDTO {
        ExportSchema.PreferencesDTO(
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            morningSummaryEnabled: true, morningSummaryHour: 9, morningSummaryMinute: 0,
            trashRetentionDays: 30, defaultTaskListSort: "manualPosition"
        )
    }

    private func attachmentData(in p: PersistenceController) async -> Data? {
        await p.container.viewContext.perform {
            let req = NSFetchRequest<LillistCore.Attachment>(entityName: "Attachment")
            return try? p.container.viewContext.fetch(req).first?.data
        }
    }

    private func attachmentCount(in p: PersistenceController) async -> Int {
        await p.container.viewContext.perform {
            let req = NSFetchRequest<NSFetchRequestResult>(entityName: "Attachment")
            return (try? p.container.viewContext.count(for: req)) ?? -1
        }
    }

    @Test("attachment bytes are reloaded from the assets directory")
    func restoresBytes() async throws {
        let p = try await TestStore.make()
        let taskID = UUID()
        let attID = UUID()
        let bytes = Data([0x10, 0x20, 0x30, 0x40, 0x50])

        let assets = tempDir()
        defer { try? FileManager.default.removeItem(at: assets) }
        let filename = "\(attID.uuidString)-blob.bin"
        try bytes.write(to: assets.appendingPathComponent(filename))

        let att = ExportSchema.AttachmentDTO(
            id: attID, taskID: taskID, journalEntryID: nil, kind: 0,
            filename: "blob.bin", uti: "public.data", byteSize: Int64(bytes.count),
            dataPath: "assets/\(filename)", linkPreviewJSON: nil, createdAt: Date()
        )
        let doc = ExportSchema.Document(
            version: ExportSchema.version, exportedAt: Date(),
            tasks: [taskDTO(id: taskID)], tags: [], journalEntries: [],
            attachments: [att], preferences: prefsDTO()
        )

        let importer = Importer(persistence: p)
        _ = try await importer.apply(document: doc, policy: .replaceExisting, assetsDirectory: assets)

        #expect(await attachmentCount(in: p) == 1)
        #expect(await attachmentData(in: p) == bytes)
    }

    @Test("attachments are skipped when no assets directory is given")
    func skipsWithoutAssetsDir() async throws {
        let p = try await TestStore.make()
        let taskID = UUID()
        let att = ExportSchema.AttachmentDTO(
            id: UUID(), taskID: taskID, journalEntryID: nil, kind: 0,
            filename: "x", uti: "public.data", byteSize: 1,
            dataPath: "assets/x", linkPreviewJSON: nil, createdAt: nil
        )
        let doc = ExportSchema.Document(
            version: ExportSchema.version, exportedAt: Date(),
            tasks: [taskDTO(id: taskID)], tags: [], journalEntries: [],
            attachments: [att], preferences: prefsDTO()
        )
        let importer = Importer(persistence: p)
        _ = try await importer.apply(document: doc, policy: .replaceExisting)  // no assetsDirectory
        #expect(await attachmentCount(in: p) == 0)
    }
}
