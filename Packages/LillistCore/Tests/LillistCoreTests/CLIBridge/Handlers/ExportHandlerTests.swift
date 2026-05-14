import Testing
import Foundation
@testable import LillistCore

@Suite("CLIBridge.ExportHandler")
struct ExportHandlerTests {
    @Test("Exports JSON + assets to the target directory")
    func exportsToDir() async throws {
        let p = try await TestStore.make()
        _ = try await TaskStore(persistence: p).create(title: "Demo")
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lillist-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try await CLIBridge.ExportHandler.run(directory: dir, persistence: p)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("lillist.json").path))
    }
}
