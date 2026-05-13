import Testing
@testable import LillistCore

@Suite("JournalEntryKind")
struct JournalEntryKindTests {
    @Test("Raw values stable")
    func rawValues() {
        #expect(JournalEntryKind.note.rawValue == 0)
        #expect(JournalEntryKind.statusChange.rawValue == 1)
        #expect(JournalEntryKind.attachment.rawValue == 2)
        #expect(JournalEntryKind.createdFollowUp.rawValue == 3)
    }

    @Test("System kinds are read-only")
    func systemKinds() {
        #expect(JournalEntryKind.note.isUserEditable == true)
        #expect(JournalEntryKind.statusChange.isUserEditable == false)
        #expect(JournalEntryKind.attachment.isUserEditable == true)
        #expect(JournalEntryKind.createdFollowUp.isUserEditable == false)
    }
}
