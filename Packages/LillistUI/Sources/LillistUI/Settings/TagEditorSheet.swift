import SwiftUI

/// Edit sheet for a single tag: rename, recolor, or delete.
///
/// Shared by the iOS and macOS Tags & Filters wrappers and presented via
/// `.sheet(item:)` on their stable `Form` container. Commits flow out through the
/// injected closures so the wrapper owns the `TagStore` calls; a destructive
/// delete is gated behind an in-sheet `confirmationDialog` whose copy warns about
/// the child-tag cascade (`Tag.children` is `Cascade`).
public struct TagEditorSheet: View {
    private let originalName: String
    private let originalTintHex: String?
    private let descendantCount: Int
    private let onSave: (_ name: String, _ hex: String?) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void

    @State private var name: String
    @State private var color: Color
    /// Whether the user actually touched the picker. A tag with no tint seeds the
    /// picker with a fallback swatch; without this guard a rename-only save would
    /// silently stamp that fallback as an explicit tint. Only a real interaction
    /// emits a color change.
    @State private var colorEdited = false
    @State private var showDeleteConfirmation = false

    public init(
        name: String,
        tintHex: String?,
        descendantCount: Int,
        onSave: @escaping (_ name: String, _ hex: String?) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalName = name
        self.originalTintHex = tintHex
        self.descendantCount = descendantCount
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _name = State(initialValue: name)
        _color = State(initialValue: Color(hex: tintHex) ?? Self.fallbackColor)
    }

    public var body: some View {
        EditorSheetScaffold(
            title: Text("Edit Tag", bundle: .module),
            isSaveEnabled: TagsFiltersEditing.isNameValid(name),
            onCancel: onCancel,
            onSave: { onSave(TagsFiltersEditing.normalized(name), colorEdited ? color.toHex() : originalTintHex) }
        ) {
            TextField(text: $name) { Text("Name", bundle: .module) }
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
                .submitLabel(.done)

            ColorPicker(
                selection: Binding(get: { color }, set: { color = $0; colorEdited = true }),
                supportsOpacity: false
            ) {
                Text("Color", bundle: .module)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Text("Delete Tag", bundle: .module)
            }
        }
        .confirmationDialog(
            Text("Delete Tag", bundle: .module),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: onDelete) { Text("Delete", bundle: .module) }
            Button(role: .cancel) { } label: { Text("Cancel", bundle: .module) }
        } message: {
            Text(Self.deleteConfirmationMessage(name: originalName, descendantCount: descendantCount))
        }
    }

    private static let fallbackColor = Color(hex: "#7F8FA6") ?? .gray

    /// Delete-confirmation body, branching on the cascade size. A `nonisolated
    /// static func` so it's unit-testable without rendering (mirrors
    /// `ICloudSyncSettingsSection.statusLine`).
    nonisolated static func deleteConfirmationMessage(name: String, descendantCount: Int) -> String {
        switch descendantCount {
        case ..<1:
            return String(localized: "Delete “\(name)”? It will be removed from any tasks that use it. This can’t be undone.", bundle: .module)
        case 1:
            return String(localized: "Delete “\(name)” and its 1 nested tag? Both will be removed from any tasks that use them. This can’t be undone.", bundle: .module)
        default:
            return String(localized: "Delete “\(name)” and its \(descendantCount) nested tags? All will be removed from any tasks that use them. This can’t be undone.", bundle: .module)
        }
    }
}
