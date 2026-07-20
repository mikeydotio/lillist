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
                            ForEach(ReminderListGrouping.grouped(lists)) { group in
                                Section(group.accountName) {
                                    ForEach(group.lists) { list in
                                        reminderListRow(list)
                                            .tag(Optional(list.id))
                                    }
                                }
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

    // MARK: Rows

    /// One picker row: the list's title with its incomplete-reminder count
    /// trailing, mirroring the sidebar's count-badge idiom.
    @ViewBuilder
    private func reminderListRow(_ list: ReminderListInfo) -> some View {
        HStack {
            Text(list.title)
            Spacer()
            Text(list.incompleteCount, format: .number)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: list))
    }

    private static func accessibilityLabel(for list: ReminderListInfo) -> String {
        String(localized: "\(list.title), \(list.incompleteCount) reminder\(list.incompleteCount == 1 ? "" : "s")")
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
