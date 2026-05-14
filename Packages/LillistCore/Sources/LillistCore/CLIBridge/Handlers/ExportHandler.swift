import Foundation

extension CLIBridge {
    public enum ExportHandler {
        public static func run(directory: URL, persistence: PersistenceController) async throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let prefs = PreferencesStore(persistence: persistence)
            let exporter = Exporter(persistence: persistence, preferences: prefs)
            try await exporter.export(to: directory)
        }
    }
}
