import SwiftUI

/// Edit sheet for a single saved smart filter: rename or delete.
///
/// Shared by the iOS and macOS Tags & Filters wrappers and presented via
/// `.sheet(item:)` on their stable `Form` container. Recolor and predicate editing
/// are out of scope here (issue #16 covers rename + delete); the wrapper owns the
/// `SmartFilterStore` calls behind the injected closures. Delete is gated behind an
/// in-sheet `confirmationDialog`.
public struct FilterEditorSheet: View {
    private let originalName: String
    private let onSave: (_ name: String) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void

    @State private var name: String
    @State private var showDeleteConfirmation = false

    public init(
        name: String,
        onSave: @escaping (_ name: String) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalName = name
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: name)
    }

    public var body: some View {
        EditorSheetScaffold(
            title: Text("Edit Filter", bundle: .module),
            isSaveEnabled: TagsFiltersEditing.isNameValid(name),
            onCancel: onCancel,
            onSave: { onSave(TagsFiltersEditing.normalized(name)) }
        ) {
            TextField(text: $name) { Text("Name", bundle: .module) }
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .submitLabel(.done)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete Filter", bundle: .module)
            }
        }
        .confirmationDialog(
            Text("Delete Filter", bundle: .module),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDelete) { Text("Delete", bundle: .module) }
            Button(role: .cancel) { } label: { Text("Cancel", bundle: .module) }
        } message: {
            Text(Self.deleteConfirmationMessage(name: originalName))
        }
    }

    /// Delete-confirmation body. A `nonisolated static func` so it's unit-testable
    /// without rendering.
    nonisolated static func deleteConfirmationMessage(name: String) -> String {
        String(localized: "Delete the “\(name)” filter? This can’t be undone.", bundle: .module)
    }
}
