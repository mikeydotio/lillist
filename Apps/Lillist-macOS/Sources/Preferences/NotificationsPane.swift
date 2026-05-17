import SwiftUI
import LillistCore
import LillistUI

/// macOS Preferences Notifications pane (Plan 10 Task 9).
///
/// Three sections:
/// 1. **All-day reminder time** — DatePicker bound to
///    `defaultAllDayHour`/`Minute` Prefs fields. When the user picks a
///    new time, the scheduler is told via `updateDefaultAllDayTime`
///    so layer-2 (all-day defaults) reflects the change without a
///    relaunch.
/// 2. **Morning summary** — toggle and time picker. Toggling on/off
///    calls `installMorningSummary` / `uninstallMorningSummary` on
///    the scheduler. Changing the time while enabled re-installs.
/// 3. **Permission** — current authorization status with a "Test
///    permission" button that calls `requestAuthorization()`.
struct NotificationsPane: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs: PreferencesStore.Prefs?
    @State private var permStatus: NotificationPermissions.AuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            if let b = binding {
                Section("All-day reminder time") {
                    DatePicker(
                        "Default time",
                        selection: hmBinding(b),
                        displayedComponents: .hourAndMinute
                    )
                }
                Section("Morning summary") {
                    Toggle("Send a morning summary", isOn: b.morningSummaryEnabled)
                    if b.wrappedValue.morningSummaryEnabled {
                        DatePicker(
                            "Summary time",
                            selection: morningBinding(b),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
                Section("Permission") {
                    HStack {
                        permissionLabel
                        Spacer()
                        Button("Test permission") {
                            Task {
                                permStatus = await environment.notificationPermissions.requestAuthorization()
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .fixedSize() // Plan 15 Task 26: pane self-sizes; window animates
        .task { await subscribe() }
        .onChange(of: prefs) { old, new in
            guard let new else { return }
            Task { try? await environment.preferencesStore.update { $0 = new } }
            applySchedulerSideEffects(old: old, new: new)
        }
    }

    private func subscribe() async {
        if prefs == nil {
            prefs = try? await environment.preferencesStore.read()
        }
        permStatus = await environment.notificationPermissions.currentStatus()
        for await snapshot in environment.preferencesStore.prefsStream {
            if snapshot != prefs {
                prefs = snapshot
            }
        }
    }

    @ViewBuilder private var permissionLabel: some View {
        switch permStatus {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notDetermined:
            Label("Not yet requested", systemImage: "questionmark.circle")
        }
    }

    private var binding: Binding<PreferencesStore.Prefs>? {
        guard prefs != nil else { return nil }
        return Binding(get: { prefs! }, set: { prefs = $0 })
    }

    private func hmBinding(_ b: Binding<PreferencesStore.Prefs>) -> Binding<Date> {
        Binding(
            get: { HourMinuteDate.date(hour: Int(b.wrappedValue.defaultAllDayHour), minute: Int(b.wrappedValue.defaultAllDayMinute)) },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                b.wrappedValue.defaultAllDayHour = Int16(comps.hour ?? 9)
                b.wrappedValue.defaultAllDayMinute = Int16(comps.minute ?? 0)
            }
        )
    }

    private func morningBinding(_ b: Binding<PreferencesStore.Prefs>) -> Binding<Date> {
        Binding(
            get: { HourMinuteDate.date(hour: Int(b.wrappedValue.morningSummaryHour), minute: Int(b.wrappedValue.morningSummaryMinute)) },
            set: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: $0)
                b.wrappedValue.morningSummaryHour = Int16(comps.hour ?? 9)
                b.wrappedValue.morningSummaryMinute = Int16(comps.minute ?? 0)
            }
        )
    }

    /// Plan 10: the prefs UI is the source of truth, but the
    /// NotificationScheduler caches default times / summary state at
    /// boot. Reflect any change synchronously so the next mutation
    /// doesn't continue to schedule with the old values.
    private func applySchedulerSideEffects(
        old: PreferencesStore.Prefs?,
        new: PreferencesStore.Prefs
    ) {
        let scheduler = environment.notificationScheduler
        if old?.defaultAllDayHour != new.defaultAllDayHour
            || old?.defaultAllDayMinute != new.defaultAllDayMinute {
            Task {
                await scheduler.updateDefaultAllDayTime(
                    hour: Int(new.defaultAllDayHour),
                    minute: Int(new.defaultAllDayMinute)
                )
            }
        }
        let oldEnabled = old?.morningSummaryEnabled ?? false
        let newEnabled = new.morningSummaryEnabled
        let oldHour = old?.morningSummaryHour
        let oldMin = old?.morningSummaryMinute
        let timeChanged = oldHour != new.morningSummaryHour
            || oldMin != new.morningSummaryMinute
        if newEnabled && (!oldEnabled || timeChanged) {
            Task {
                await scheduler.installMorningSummary(
                    hour: Int(new.morningSummaryHour),
                    minute: Int(new.morningSummaryMinute)
                )
            }
        } else if !newEnabled && oldEnabled {
            Task { await scheduler.uninstallMorningSummary() }
        }
    }
}
