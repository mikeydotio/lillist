import SwiftUI
import LillistCore
import LillistUI
import AppKit

/// macOS Preferences pane mirroring the iOS `ICloudSyncSection`.
/// Pipes `AppEnvironment` state into the cross-platform
/// `ICloudSyncSettingsSection`. Owns the migration sheet state.
struct ICloudSyncPane: View {
    @Environment(AppEnvironment.self) private var environment

    /// One presentation slot for every sync modal — see `SyncSheetRoute` for why
    /// a single `.sheet(item:)` replaces the previous stack of four `.sheet`s.
    @State private var route: SyncSheetRoute?
    @State private var pendingDirection: SyncMigrationConfirmationDialog.Direction?
    @State private var taskCounts: TaskStore.SyncCounts?

    var body: some View {
        Form {
            ICloudSyncSettingsSection(
                viewState: viewState,
                actions: actions
            )
        }
        .formStyle(.grouped)
        .padding(LillistSpacing.l)
        .frame(width: PreferencesMetrics.contentWidth)
        .fixedSize()
        .task { await refreshCounts() }
        // Re-count after a sync settles so the mirrored figure tracks reality.
        .onChange(of: environment.syncMonitor.indicator) { _, _ in
            Task { await refreshCounts() }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            actions: {
                Button("Replace", role: .destructive) {
                    if let direction = pendingDirection {
                        triggerEnable(direction: direction)
                    }
                    pendingDirection = nil
                }
                Button("Cancel", role: .cancel) { pendingDirection = nil }
            },
            message: { Text(confirmationMessage) }
        )
        .sheet(item: $route) { sheet in
            switch sheet {
            case .choice:
                SyncMigrationChoiceSheet(
                    onReplaceICloud: { route = nil; pendingDirection = .replaceICloud },
                    onReplaceLocal: { route = nil; pendingDirection = .replaceLocal },
                    onCancel: { route = nil }
                )
                .frame(width: 520, height: 480)
            case .disable:
                SyncDisableConfirmationSheet(
                    // `triggerDisable` → `runMigration` swaps `route` straight to
                    // `.progress`, so the dismiss-one-present-another conflict
                    // that used to nuke Settings can't happen.
                    onSyncFirst: { triggerDisable(strategy: .syncFirst) },
                    onDisableNow: { triggerDisable(strategy: .now) },
                    onCancel: { route = nil }
                )
                .frame(width: 480, height: 340)
            case .pauseExplainer:
                PauseExplainerDialog(
                    reason: environment.pauseReason ?? .unknown,
                    onOpenSettings: openSystemSettings,
                    onDisableSync: { route = .disable },
                    onDismiss: { route = nil }
                )
                .frame(width: 460, height: 340)
            case .progress(let phase):
                SyncMigrationProgressSheet(
                    phase: phase,
                    onDismissAfterCompletion: { route = nil }
                )
                .frame(width: 520, height: 380)
                .interactiveDismissDisabled(true)
            }
        }
    }

    private var viewState: ICloudSyncSettingsSection.ViewState {
        let mode = environment.currentSyncMode
        let status: SyncIndicator
        if mode == .iCloudSync {
            if let reason = environment.pauseReason {
                status = .paused(reason: reason)
            } else {
                status = environment.syncMonitor.indicator
            }
        } else {
            status = .idle(lastSync: nil)
        }
        let iCloudAvailable = isAvailable(environment.accountState)
        let isToggleDisabled = mode == .localOnly && !iCloudAvailable
        let footer: String? = isToggleDisabled
            ? String(localized: "Sign into iCloud to enable sync.")
            : nil
        return .init(
            mode: mode,
            status: status,
            isToggleDisabled: isToggleDisabled,
            disabledFooter: footer,
            localTaskCount: taskCounts?.local,
            mirroredTaskCount: taskCounts?.mirrored
        )
    }

    private func refreshCounts() async {
        taskCounts = try? await environment.taskStore.syncCounts()
    }

    private var actions: ICloudSyncSettingsSection.Actions {
        .init(
            onToggle: handleToggle,
            onOpenSystemSettings: openSystemSettings,
            onPausedTap: { route = .pauseExplainer }
        )
    }

    private func handleToggle(_ on: Bool) {
        route = .afterToggle(on: on)
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        if case .available = state { return true }
        return false
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { pendingDirection != nil }, set: { if !$0 { pendingDirection = nil } })
    }

    private var confirmationTitle: String {
        switch pendingDirection {
        case .replaceICloud: return String(localized: "Replace iCloud with This Device?")
        case .replaceLocal: return String(localized: "Replace This Device with iCloud?")
        case nil: return ""
        }
    }

    private var confirmationMessage: String {
        switch pendingDirection {
        case .replaceICloud:
            return String(localized: "This permanently replaces iCloud's data with what's on this device. Other devices syncing this iCloud account will see this change. This cannot be undone.")
        case .replaceLocal:
            return String(localized: "This permanently replaces this device's data with what's in iCloud. This cannot be undone.")
        case nil: return ""
        }
    }

    private func triggerEnable(direction: SyncMigrationConfirmationDialog.Direction) {
        let dir: EnableDirection = direction == .replaceICloud ? .replaceICloud : .replaceLocal
        Task { @MainActor in await runMigration { coordinator, storeURL in
            try await coordinator.beginEnable(direction: dir, storeURL: storeURL)
        }}
    }

    private func triggerDisable(strategy: DisableStrategy) {
        Task { @MainActor in await runMigration { coordinator, storeURL in
            try await coordinator.beginDisable(strategy: strategy, storeURL: storeURL)
        }}
    }

    @MainActor
    private func runMigration(_ kickoff: @MainActor (MigrationCoordinator, URL) async throws -> Void) async {
        let storeURL = environment.storeURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
        let coordinator = environment.migrationCoordinator
        let phaseTask = Task { @MainActor [coordinator] in
            for await phase in coordinator.progressStream {
                route = .progress(phase)
            }
        }
        defer { phaseTask.cancel() }
        route = .progress(.preparing)
        do {
            try await kickoff(coordinator, storeURL)
        } catch {
            route = .progress(.failed(reason: "\(error)"))
        }
    }
}
