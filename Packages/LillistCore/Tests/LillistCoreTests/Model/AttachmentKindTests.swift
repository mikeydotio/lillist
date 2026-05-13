import Testing
@testable import LillistCore

@Suite("AttachmentKind")
struct AttachmentKindTests {
    @Test("Raw values stable")
    func rawValues() {
        #expect(AttachmentKind.image.rawValue == 0)
        #expect(AttachmentKind.file.rawValue == 1)
        #expect(AttachmentKind.linkPreview.rawValue == 2)
    }

    @Test("All cases enumerable")
    func allCases() {
        #expect(AttachmentKind.allCases.count == 3)
    }
}
