import Testing
import Foundation
@testable import LillistCore

@Suite("SyncMode")
struct SyncModeTests {
    @Test("Raw values are the documented storage literals")
    func rawValuesAreStable() {
        // These literals appear in App Group UserDefaults and the
        // MigrationJournal JSON file. Changing them is a storage
        // schema break.
        #expect(SyncMode.localOnly.rawValue == "localOnly")
        #expect(SyncMode.iCloudSync.rawValue == "iCloudSync")
    }

    @Test("Default mode preserves Plan-20-and-earlier upgrade behavior")
    func defaultIsICloudSync() {
        #expect(SyncMode.default == .iCloudSync)
    }

    @Test("CaseIterable lists both modes")
    func caseIterable() {
        #expect(SyncMode.allCases == [.localOnly, .iCloudSync])
    }

    @Test("Round-trips through Codable")
    func codable() throws {
        let encoded = try JSONEncoder().encode([SyncMode.localOnly, .iCloudSync])
        let decoded = try JSONDecoder().decode([SyncMode].self, from: encoded)
        #expect(decoded == [.localOnly, .iCloudSync])
    }
}
