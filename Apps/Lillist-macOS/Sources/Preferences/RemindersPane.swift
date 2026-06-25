import SwiftUI
import AppKit
import LillistCore

/// macOS Preferences pane for "Tasks from Reminders". Mirrors the iOS
/// `RemindersImportSection`: an enable toggle, a list dropdown, and a
/// "Drain now" button.
///
/// Device-coupled, not synced — the enable flag and selected list identifier
/// live in `DevicePreferencesStore` (a Reminders `calendarIdentifier` is
/// device/account local), so this pane reads/writes the environment's stores
/// directly with local `@State` rather than the `PreferencesStore.Prefs`
/// binding the other panes use.
struct RemindersPane: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var enabled = false
    @State private var selectedListID: String?
    @State private var lists: [ReminderListInfo] = []
    @State private var authorization: RemindersAuthorization = .notDetermined
    @State private var didLoad = false
    @State private var isDraining = false
    @State private var drainMessage: String?

    var body: some View {
        Form {
            Section("Tasks from Reminders") {
                Toggle("Import from a Reminders list", isOn: enabledBinding)

                if enabled {
                    switch authorization {
                    case .authorized:
                        Picker("List", selection: listSelectionBinding) {
                            Text("None").tag(String?.none)
                            ForEach(lists) { list in
                                Text(list.title).tag(Optional(list.id))
                            }
                        }
                        HStack {
                            Button("Drain now") { Task { await drainNow() } }
                                .disabled(selectedListID == nil || isDraining)
                            if let drainMessage {
                                Text(drainMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    case .denied:
                        Text("Reminders access is off. Turn it on in System Settings ▸ Privacy & Security ▸ Reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Open System Settings") { openRemindersPrivacy() }
                    case .notDetermined:
                        Button("Grant Reminders access") { Task { await requestAccess() } }
                    }
                }
            }
            Section {
                Text("When enabled, Lillist empties the chosen list into new tasks each time it becomes active — title, notes, and due date carry across, and the reminder is removed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: PreferencesMetrics.contentWidth)
        .fixedSize() // Plan 15 Task 26: pane self-sizes height; window animates.
        .task { await loadIfNeeded() }
    }

    // MARK: Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { enabled },
            set: { newValue in
                enabled = newValue
                Task { await setEnabled(newValue) }
            }
        )
    }

    private var listSelectionBinding: Binding<String?> {
        Binding(
            get: { selectedListID },
            set: { newValue in
                selectedListID = newValue
                drainMessage = nil
                Task { await environment.devicePreferences.setRemindersImportListID(newValue) }
            }
        )
    }

    // MARK: Actions

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        didLoad = true
        enabled = await environment.devicePreferences.remindersImportEnabled()
        selectedListID = await environment.devicePreferences.remindersImportListID()
        authorization = await environment.remindersGateway.authorization()
        if enabled, authorization == .authorized {
            await refreshLists()
        }
    }

    private func setEnabled(_ value: Bool) async {
        await environment.devicePreferences.setRemindersImportEnabled(value)
        guard value else { return }
        if authorization == .notDetermined {
            await requestAccess()
        } else if authorization == .authorized {
            await refreshLists()
        }
    }

    private func requestAccess() async {
        _ = await environment.remindersGateway.requestAccess()
        authorization = await environment.remindersGateway.authorization()
        if authorization == .authorized {
            await refreshLists()
        }
    }

    private func refreshLists() async {
        lists = (try? await environment.remindersGateway.lists()) ?? []
    }

    private func drainNow() async {
        isDraining = true
        let count = await environment.remindersImporter.drainIfNeeded()
        isDraining = false
        drainMessage = count == 1 ? "Imported 1 task." : "Imported \(count) tasks."
    }

    private func openRemindersPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }
}
