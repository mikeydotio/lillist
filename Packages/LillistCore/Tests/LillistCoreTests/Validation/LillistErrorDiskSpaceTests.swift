import Testing
import Foundation
@testable import LillistCore

@Suite("LillistError.insufficientDiskSpace")
struct LillistErrorDiskSpaceTests {
    @Test("insufficientDiskSpace is Equatable on both byte fields")
    func equatable() {
        let a = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 50)
        let b = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 50)
        let c = LillistError.insufficientDiskSpace(neededBytes: 100, availableBytes: 49)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("errorDescription names both the needed and available byte counts")
    func description() {
        let err = LillistError.insufficientDiskSpace(neededBytes: 4096, availableBytes: 1024)
        let text = err.errorDescription ?? ""
        #expect(text.contains("4096"))
        #expect(text.contains("1024"))
    }
}
