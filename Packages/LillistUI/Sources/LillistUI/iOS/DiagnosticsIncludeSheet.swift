import SwiftUI
import UniformTypeIdentifiers

/// Pure presenter for the "Prepare diagnostic package" include step: two
/// toggles plus Create / Cancel. Owns no state and reads no environment — data
/// and actions arrive via `init` (container/presenter split), so it renders in
/// snapshot/tour tests with frozen bindings and mock closures.
public struct DiagnosticsIncludeSheet: View {
    @Binding private var includeLogs: Bool
    @Binding private var includeStore: Bool
    private let onCreate: () -> Void
    private let onCancel: () -> Void

    public init(
        includeLogs: Binding<Bool>,
        includeStore: Binding<Bool>,
        onCreate: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._includeLogs = includeLogs
        self._includeStore = includeStore
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Diagnostic logs", isOn: $includeLogs)
                    Toggle("Copy of data store", isOn: $includeStore)
                } footer: {
                    Text("The data store copy contains all of your task content. The package never leaves your device unless you share it.")
                }
            }
            .navigationTitle("Prepare package")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: onCreate)
                        .disabled(!includeLogs && !includeStore)
                }
            }
        }
    }
}

/// Minimal `FileDocument` wrapping a finished diagnostic `.zip` for export via
/// `.fileExporter`. Read-into-memory is fine: diagnostic packages are modest and
/// this avoids a custom `Transferable`. Shared by the iOS and macOS surfaces.
public struct DiagnosticZipDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.zip] }

    public var data: Data

    public init(url: URL) throws {
        self.data = try Data(contentsOf: url)
    }

    public init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
