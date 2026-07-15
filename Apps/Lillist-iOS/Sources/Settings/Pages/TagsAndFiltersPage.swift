import SwiftUI
import LillistCore
import LillistUI

/// Settings → Tags & Filters. Wraps the env-coupled `TagsAndFiltersSection` in the
/// shared sub-page chrome and **hosts the edit modal here**, on the
/// `SettingsDetailScreen` container — not inside the section's `Section`. A `.sheet`
/// attached to Form-row content inside this pushed nav-destination-in-a-sheet
/// present-then-dismisses and nukes the whole Settings sheet (see
/// `TagsAndFiltersModel`).
struct TagsAndFiltersPage: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = TagsAndFiltersModel()

    var body: some View {
        SettingsDetailScreen("Tags & Filters") {
            TagsAndFiltersSection(model: model)
        }
        .sheet(item: $model.route) { route in
            editSheet(for: route)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            presenting: model.errorMessage
        ) { _ in
            Button("OK") { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func editSheet(for route: TagsFiltersEditRoute) -> some View {
        switch route {
        case .tag(let node):
            TagEditorSheet(
                name: node.name,
                tintHex: node.tintHex,
                descendantCount: node.descendantCount,
                onSave: { name, hex in model.saveTag(node, name: name, hex: hex, environment) },
                onDelete: { model.deleteTag(node, environment) },
                onCancel: { model.route = nil }
            )
        case .filter(let row):
            FilterEditorSheet(
                name: row.name,
                onSave: { name in model.saveFilter(row, name: name, environment) },
                onDelete: { model.deleteFilter(row, environment) },
                onCancel: { model.route = nil }
            )
        }
    }
}
