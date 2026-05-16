import SwiftUI
import LillistCore
import LillistUI

struct NotificationsSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var permStatus: NotificationPermissions.AuthorizationStatus = .notDetermined

    var body: some View {
        Section("All-day reminder time") {
            DatePicker("Default time", selection: hmBinding, displayedComponents: .hourAndMinute)
        }
        Section("Morning summary") {
            Toggle("Send a morning summary", isOn: $prefs.morningSummaryEnabled)
            if prefs.morningSummaryEnabled {
                DatePicker("Summary time", selection: morningBinding, displayedComponents: .hourAndMinute)
            }
        }
        Section("Permission") {
            HStack {
                statusLabel
                Spacer()
                Button("Test permission") {
                    Task {
                        permStatus = await environment.notificationPermissions.requestAuthorization()
                    }
                }
            }
            if permStatus == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .task { permStatus = await environment.notificationPermissions.currentStatus() }
        .onChange(of: prefs.morningSummaryEnabled) { _, _ in applyMorningSummaryChange() }
        .onChange(of: prefs.morningSummaryHour) { _, _ in applyMorningSummaryChange() }
        .onChange(of: prefs.morningSummaryMinute) { _, _ in applyMorningSummaryChange() }
        .onChange(of: prefs.defaultAllDayHour) { _, _ in applyAllDayChange() }
        .onChange(of: prefs.defaultAllDayMinute) { _, _ in applyAllDayChange() }
    }

    @ViewBuilder private var statusLabel: some View {
        switch permStatus {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .notDetermined:
            Label("Not yet requested", systemImage: "questionmark.circle")
        }
    }

    private var hmBinding: Binding<Date> {
        Binding(
            get: { HourMinuteDate.date(hour: Int(prefs.defaultAllDayHour), minute: Int(prefs.defaultAllDayMinute)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                prefs.defaultAllDayHour = Int16(c.hour ?? 9)
                prefs.defaultAllDayMinute = Int16(c.minute ?? 0)
            }
        )
    }

    private var morningBinding: Binding<Date> {
        Binding(
            get: { HourMinuteDate.date(hour: Int(prefs.morningSummaryHour), minute: Int(prefs.morningSummaryMinute)) },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                prefs.morningSummaryHour = Int16(c.hour ?? 9)
                prefs.morningSummaryMinute = Int16(c.minute ?? 0)
            }
        )
    }

    private func applyAllDayChange() {
        let scheduler = environment.notificationScheduler
        let h = Int(prefs.defaultAllDayHour)
        let m = Int(prefs.defaultAllDayMinute)
        Task { await scheduler.updateDefaultAllDayTime(hour: h, minute: m) }
    }

    private func applyMorningSummaryChange() {
        let scheduler = environment.notificationScheduler
        let enabled = prefs.morningSummaryEnabled
        let h = Int(prefs.morningSummaryHour)
        let m = Int(prefs.morningSummaryMinute)
        Task {
            if enabled {
                await scheduler.installMorningSummary(hour: h, minute: m)
            } else {
                await scheduler.uninstallMorningSummary()
            }
        }
    }
}
