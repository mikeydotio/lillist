import Testing
import Foundation
@testable import LillistCore

/// Wave 1 — the on-disk backup package writer/reader (issue #7).
@Suite("TaskBackupStore")
struct TaskBackupStoreTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lillist-backup-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    /// Date-free by default so encode→ISO8601→decode round-trips exactly
    /// (ISO8601 drops sub-second precision — see engineering-notes 2026-05-14).
    private func taskDTO(
        id: UUID = UUID(),
        title: String = "Task",
        tagIDs: [UUID] = [],
        schemaVersion: Int = CloudKitSchema.currentVersion
    ) -> ExportSchema.TaskDTO {
        ExportSchema.TaskDTO(
            id: id, title: title, notes: "", status: 0,
            start: nil, startHasTime: false, deadline: nil, deadlineHasTime: false,
            position: 1, isPinned: false, parentID: nil, tagIDs: tagIDs,
            createdAt: nil, modifiedAt: nil, closedAt: nil, deletedAt: nil,
            schemaVersion: schemaVersion
        )
    }

    private func record(
        _ dto: ExportSchema.TaskDTO,
        journal: [ExportSchema.JournalEntryDTO] = [],
        attachments: [ExportSchema.AttachmentDTO] = []
    ) -> BackupPackageSchema.TaskBackupRecord {
        BackupPackageSchema.TaskBackupRecord(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: dto.schemaVersion,
            task: dto,
            journalEntries: journal,
            attachments: attachments
        )
    }

    @Test("upsert writes a task file that round-trips through the reader")
    func upsertRoundTrip() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let dto = taskDTO(title: "Ship it")
        let rec = record(dto)
        try await store.upsert([rec], assets: [])

        let reader = BackupPackageReader(packageDirectory: dir)
        let read = try reader.readTaskRecords()
        #expect(read.count == 1)
        #expect(read.first == rec)
    }

    @Test("upsert stages attachment blobs into assets/")
    func upsertWritesAssets() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let att = ExportSchema.AttachmentDTO(
            id: UUID(), taskID: nil, journalEntryID: nil, kind: 0,
            filename: "blob.bin", uti: "public.data", byteSize: Int64(bytes.count),
            dataPath: "assets/blob.bin", linkPreviewJSON: nil, createdAt: nil
        )
        let rec = record(taskDTO(), attachments: [att])
        try await store.upsert([rec], assets: [.init(filename: "blob.bin", bytes: bytes)])

        let assetURL = dir.appendingPathComponent("assets/blob.bin")
        #expect(FileManager.default.fileExists(atPath: assetURL.path))
        #expect(try Data(contentsOf: assetURL) == bytes)
    }

    @Test("remove deletes the task file and its referenced assets")
    func removeCleansAssets() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let id = UUID()
        let bytes = Data([0x01, 0x02])
        let att = ExportSchema.AttachmentDTO(
            id: UUID(), taskID: id, journalEntryID: nil, kind: 0,
            filename: "a.bin", uti: "public.data", byteSize: 2,
            dataPath: "assets/a.bin", linkPreviewJSON: nil, createdAt: nil
        )
        try await store.upsert([record(taskDTO(id: id), attachments: [att])],
                               assets: [.init(filename: "a.bin", bytes: bytes)])

        let taskURL = dir.appendingPathComponent("tasks/\(id.uuidString).json")
        let assetURL = dir.appendingPathComponent("assets/a.bin")
        #expect(FileManager.default.fileExists(atPath: taskURL.path))
        #expect(FileManager.default.fileExists(atPath: assetURL.path))

        try await store.remove(taskIDs: [id])
        #expect(!FileManager.default.fileExists(atPath: taskURL.path))
        #expect(!FileManager.default.fileExists(atPath: assetURL.path))
    }

    @Test("sidecars + manifest write and read back")
    func sidecarsAndManifest() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let tag = ExportSchema.TagDTO(id: UUID(), name: "Work", tintColor: "#FF0000", parentID: nil, position: 1)
        let prefs = ExportSchema.PreferencesDTO(
            defaultAllDayHour: 8, defaultAllDayMinute: 30,
            morningSummaryEnabled: false, morningSummaryHour: 7, morningSummaryMinute: 15,
            trashRetentionDays: 14, defaultTaskListSort: "deadline"
        )
        try await store.writeSidecars(tags: [tag], preferences: prefs)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.writeManifest(.init(
            backupSchemaVersion: BackupPackageSchema.version,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion,
            updatedAt: when,
            taskCount: 3
        ))

        let reader = BackupPackageReader(packageDirectory: dir)
        let manifest = try #require(try reader.readManifest())
        #expect(manifest.cloudKitSchemaVersion == CloudKitSchema.currentVersion)
        #expect(manifest.taskCount == 3)
        #expect(manifest.updatedAt == when)

        let doc = try reader.assembleDocument()
        #expect(doc.tags == [tag])
        #expect(doc.preferences == prefs)
    }

    @Test("replaceAll reclaims orphaned task files and assets")
    func replaceAllReclaims() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let stale = UUID()
        try await store.upsert([record(taskDTO(id: stale))], assets: [])
        #expect(try await store.taskFileCount() == 1)

        let fresh = taskDTO(title: "Kept")
        let prefs = ExportSchema.PreferencesDTO(
            defaultAllDayHour: 9, defaultAllDayMinute: 0,
            morningSummaryEnabled: true, morningSummaryHour: 9, morningSummaryMinute: 0,
            trashRetentionDays: 30, defaultTaskListSort: "manualPosition"
        )
        try await store.replaceAll(
            records: [record(fresh)], assets: [], tags: [], preferences: prefs,
            cloudKitSchemaVersion: CloudKitSchema.currentVersion,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let reader = BackupPackageReader(packageDirectory: dir)
        let records = try reader.readTaskRecords()
        #expect(records.count == 1)
        #expect(records.first?.task.id == fresh.id)
        let staleURL = dir.appendingPathComponent("tasks/\(stale.uuidString).json")
        #expect(!FileManager.default.fileExists(atPath: staleURL.path))
    }

    @Test("isEmpty reflects whether any task file exists")
    func isEmptyTracksTasks() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)
        #expect(await store.isEmpty())
        try await store.upsert([record(taskDTO())], assets: [])
        #expect(!(await store.isEmpty()))
    }

    @Test("assembleDocument flattens owned journal entries and attachments")
    func assembleFlattens() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskBackupStore(packageDirectory: dir)

        let id = UUID()
        let entry = ExportSchema.JournalEntryDTO(
            id: UUID(), taskID: id, kind: 0, body: "note", payload: nil,
            createdAt: nil, editedAt: nil
        )
        let att = ExportSchema.AttachmentDTO(
            id: UUID(), taskID: id, journalEntryID: nil, kind: 0,
            filename: "f", uti: "public.data", byteSize: 0,
            dataPath: nil, linkPreviewJSON: "{}", createdAt: nil
        )
        try await store.upsert([record(taskDTO(id: id), journal: [entry], attachments: [att])], assets: [])

        let doc = try BackupPackageReader(packageDirectory: dir).assembleDocument()
        #expect(doc.tasks.count == 1)
        #expect(doc.journalEntries == [entry])
        #expect(doc.attachments == [att])
    }
}
