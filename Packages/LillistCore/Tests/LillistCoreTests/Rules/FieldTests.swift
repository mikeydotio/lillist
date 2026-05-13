import Foundation
import Testing
@testable import LillistCore

@Suite("Field")
struct FieldTests {
    @Test("Raw values are stable")
    func rawValuesStable() {
        #expect(Field.title.rawValue == "title")
        #expect(Field.notes.rawValue == "notes")
        #expect(Field.journalText.rawValue == "journalText")
        #expect(Field.tag.rawValue == "tag")
        #expect(Field.status.rawValue == "status")
        #expect(Field.start.rawValue == "start")
        #expect(Field.deadline.rawValue == "deadline")
        #expect(Field.createdAt.rawValue == "createdAt")
        #expect(Field.modifiedAt.rawValue == "modifiedAt")
        #expect(Field.closedAt.rawValue == "closedAt")
        #expect(Field.hasAttachments.rawValue == "hasAttachments")
        #expect(Field.hasChildren.rawValue == "hasChildren")
        #expect(Field.hasNudges.rawValue == "hasNudges")
        #expect(Field.isPinned.rawValue == "isPinned")
        #expect(Field.ancestor.rawValue == "ancestor")
        #expect(Field.recurrence.rawValue == "recurrence")
        #expect(Field.inTrash.rawValue == "inTrash")
    }

    @Test("All design Section 5 fields enumerated")
    func allCases() {
        #expect(Field.allCases.count == 17)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for f in Field.allCases {
            let data = try JSONEncoder().encode(f)
            let decoded = try JSONDecoder().decode(Field.self, from: data)
            #expect(decoded == f)
        }
    }
}
