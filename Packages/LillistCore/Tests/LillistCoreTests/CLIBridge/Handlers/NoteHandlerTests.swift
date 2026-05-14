import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.NoteHandler")
struct NoteHandlerTests {
    @Test("Appends a journal note")
    func appendsNote() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        let noteID = try await CLIBridge.NoteHandler.run(
            token: id.uuidString, body: "hello", persistence: p
        )
        let entries = try await JournalStore(persistence: p).entries(forTask: id)
        #expect(entries.contains { $0.id == noteID })
    }

    @Test("Rejects empty body")
    func rejectsEmpty() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        await #expect(throws: LillistError.self) {
            _ = try await CLIBridge.NoteHandler.run(token: id.uuidString, body: "  ", persistence: p)
        }
    }
}
