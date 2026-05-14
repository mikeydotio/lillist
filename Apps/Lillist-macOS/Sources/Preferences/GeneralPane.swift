import SwiftUI
import LillistCore

/// macOS Preferences General pane (Plan 10 Task 8).
///
/// Reads the live `Prefs` snapshot through `@Environment(AppEnvironment.self)`,
/// then writes back through `preferencesStore.update { … }` on every
/// change. The async-write pattern matches every other Settings binding
/// in this repo.
struct GeneralPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var loadError: Error?

    var body: some View {
        Form {
            if let prefsBinding {
                Section("Defaults") {
                    Picker("Default task list sort", selection: prefsBinding.defaultTaskListSort) {
                        ForEach(SortField.allCases, id: \.self) { field in
                            Text(field.displayName).tag(field)
                        }
                    }
                    ColorPicker("Default tag tint", selection: tagTintBinding)
                }
            } else if let loadError {
                Text("Couldn't load preferences: \(loadError.localizedDescription)")
                    .foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task { await load() }
        .onChange(of: prefs) { _, new in
            guard let new else { return }
            // Each granular toggle writes the full Prefs snapshot back.
            // For sub-fields that need cross-cutting side effects (e.g.
            // notification scheduler reconciliation on the Notifications
            // pane), wrap the binding setter instead.
            Task { try? await environment.preferencesStore.update { $0 = new } }
        }
    }

    private var prefsBinding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private var tagTintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs?.defaultTagTintHex) ?? .gray },
            set: { newColor in
                guard prefs != nil else { return }
                prefs!.defaultTagTintHex = newColor.toHex() ?? "#7F8FA6"
            }
        )
    }

    private func load() async {
        do {
            prefs = try await environment.preferencesStore.read()
        } catch {
            loadError = error
        }
    }
}

private extension SortField {
    var displayName: String {
        switch self {
        case .manualPosition: return "Manual"
        case .start: return "Start date"
        case .deadline: return "Deadline"
        case .title: return "Title"
        case .createdAt: return "Created"
        case .modifiedAt: return "Modified"
        case .closedAt: return "Closed"
        case .status: return "Status"
        }
    }
}
