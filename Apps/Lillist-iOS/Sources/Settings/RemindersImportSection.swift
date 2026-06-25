import SwiftUI
import LillistCore
import UIKit

/// Settings → Tasks from Reminders. Lets the user turn on draining of a
/// chosen Reminders.app list into top-level Lillist tasks on each activation.
///
/// Device-coupled, not synced: the enable flag and selected list identifier
/// live in `DevicePreferencesStore` (a Reminders `calendarIdentifier` is
/// device/account local), so this section reads/writes the environment's
/// stores directly with local `@State` rather than the `PreferencesStore.Prefs`
/// binding the other sections use.
struct RemindersImportSection: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var enabled = false
    @State private var selectedListID: String?
    @State private var lists: [ReminderListInfo] = []
    @State private var authorization: RemindersAuthorization = .notDetermined
    @State private var didLoad = false
    @State private var isDraining = false
    @State private var drainMessage: String?

    var body: some View {
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
                    Button("Drain now") { Task { await drainNow() } }
                        .disabled(selectedListID == nil || isDraining)
                    if let drainMessage {
                        Text(drainMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .denied:
                    Text("Reminders access is off. Turn it on in Settings ▸ Privacy & Security ▸ Reminders.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                case .notDetermined:
                    Button("Grant Reminders access") { Task { await requestAccess() } }
                }
            }

            Text("When enabled, Lillist empties the chosen list into new tasks each time it opens — title, notes, and due date carry across, and the reminder is removed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
}
