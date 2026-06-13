import SwiftUI
import LillistCore
import LillistUI

struct NotificationsSection: View {
    @Binding var prefs: PreferencesStore.Prefs
    @Environment(AppEnvironment.self) private var environment
    @State private var permStatus: NotificationPermissions.AuthorizationStatus = .notDetermined

    private struct AllDayKey: Hashable { let h: Int16; let m: Int16 }
    private struct MorningKey: Hashable { let enabled: Bool; let h: Int16; let m: Int16 }

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
            }
            switch permStatus {
            case .notDetermined:
                Button("Request permission") {
                    Task {
                        permStatus = await environment.notificationPermissions.requestAuthorization()
                    }
                }
            case .denied:
                Button("Open Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .authorized:
                EmptyView()
            }
        }
        .task { permStatus = await environment.notificationPermissions.currentStatus() }
        .task(id: AllDayKey(h: prefs.defaultAllDayHour, m: prefs.defaultAllDayMinute)) {
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch { return }
            applyAllDayChange()
        }
        .task(id: MorningKey(
            enabled: prefs.morningSummaryEnabled,
            h: prefs.morningSummaryHour,
            m: prefs.morningSummaryMinute
        )) {
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch { return }
            applyMorningSummaryChange()
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch permStatus {
        case .authorized:
            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(RainbowPalette.growthGreen.ink)
        case .denied:
            Label("Denied", systemImage: "exclamationmark.triangle.fill").foregroundStyle(RainbowPalette.cautionAmber.ink)
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
