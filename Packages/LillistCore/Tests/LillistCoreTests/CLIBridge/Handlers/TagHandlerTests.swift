import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.TagHandler")
struct TagHandlerTests {
    @Test("Adds a tag and creates it if missing")
    func addsTag() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.TagHandler.run(token: id.uuidString, tokens: ["+#Work"], persistence: p)
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 1)
    }

    @Test("Removes a tag")
    func removesTag() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.TagHandler.run(token: id.uuidString, tokens: ["+#Work"], persistence: p)
        try await CLIBridge.TagHandler.run(token: id.uuidString, tokens: ["-#Work"], persistence: p)
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.isEmpty)
    }

    @Test("Bare #tag implies +#tag")
    func bareAdds() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.TagHandler.run(token: id.uuidString, tokens: ["#Work"], persistence: p)
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 1)
    }

    @Test("Mixed adds and removes apply in order")
    func mixed() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        try await CLIBridge.TagHandler.run(
            token: id.uuidString,
            tokens: ["+#A", "+#B", "-#A"],
            persistence: p
        )
        let tagIDs = try await TaskStore(persistence: p).tagIDs(forTask: id)
        #expect(tagIDs.count == 1)
    }

    @Test("Invalid token throws validationFailed")
    func invalidToken() async throws {
        let p = try await TestStore.make()
        let id = try await TaskStore(persistence: p).create(title: "T")
        await #expect(throws: LillistError.self) {
            try await CLIBridge.TagHandler.run(token: id.uuidString, tokens: ["NoPrefix"], persistence: p)
        }
    }
}
