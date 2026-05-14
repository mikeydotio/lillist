import Foundation

extension CLIBridge {
    public enum AttachHandler {
        @discardableResult
        public static func run(
            token: String,
            paths: [String],
            persistence: PersistenceController
        ) async throws -> [UUID] {
            guard paths.isEmpty == false else {
                throw LillistError.validationFailed([.init(field: "paths", message: "at least one path is required")])
            }
            let r = try await Resolver.resolve(
                token: token, scope: .anywhereIncludingClosed,
                destructiveness: .readOnly, persistence: persistence
            )
            let store = AttachmentStore(persistence: persistence)
            var attached: [UUID] = []
            for path in paths {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw LillistError.validationFailed([.init(field: "path", message: "file not found at \(url.path)")])
                }
                let data = try Data(contentsOf: url)
                let id = try await store.addFile(
                    taskID: r.id,
                    filename: url.lastPathComponent,
                    uti: "public.data",
                    data: data
                )
                attached.append(id)
            }
            return attached
        }
    }
}
