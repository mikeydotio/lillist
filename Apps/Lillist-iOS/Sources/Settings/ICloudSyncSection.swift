import SwiftUI
import LillistCore
import LillistUI
import UIKit

/// Owns the iCloud-sync modal state + migration kickoff, lifted out of
/// `ICloudSyncSection` so the `.sheet(item:)` and `.confirmationDialog` can be
/// hosted by the **page** (`ICloudSyncPage`) on the `SettingsDetailScreen`
/// container rather than on a `Section`. A `.sheet` attached to `Section`/Form-row
/// content inside a pushed `NavigationStack` destination (itself inside the
/// Settings `.sheet`) presents-then-immediately-dismisses and tears the whole
/// Settings sheet down with it — see `docs/engineering-notes.md`. Hosting the
/// presentation on the stable Form container is the fix; the single-`SyncSheetRoute`
/// consolidation still stands.
@MainActor
@Observable
final class ICloudSyncModalsModel {
    /// One presentation slot for every sync modal — see `SyncSheetRoute`.
    var route: SyncSheetRoute?
    var pendingDirection: SyncMigrationConfirmationDialog.Direction?

    func handleToggle(_ on: Bool) { route = .afterToggle(on: on) }
    func showPauseExplainer() { route = .pauseExplainer }

    func confirmReplace(_ env: AppEnvironment) {
        if let direction = pendingDirection { triggerEnable(direction: direction, env) }
        pendingDirection = nil
    }

    func triggerEnable(direction: SyncMigrationConfirmationDialog.Direction, _ env: AppEnvironment) {
        let dir: EnableDirection = direction == .replaceICloud ? .replaceICloud : .replaceLocal
        Task { @MainActor in await runMigration(env) { coordinator, storeURL in
            try await coordinator.beginEnable(direction: dir, storeURL: storeURL)
        }}
    }

    func triggerDisable(strategy: DisableStrategy, _ env: AppEnvironment) {
        Task { @MainActor in await runMigration(env) { coordinator, storeURL in
            try await coordinator.beginDisable(strategy: strategy, storeURL: storeURL)
        }}
    }

    /// Drives the migration coordinator and streams phase events into `route` so
    /// the progress sheet renders the live state. `storeURL` is required; in
    /// production AppEnvironment always has one — falling back to a temp path
    /// keeps the codepath defined for test fixtures.
    private func runMigration(_ env: AppEnvironment, _ kickoff: @MainActor (MigrationCoordinator, URL) async throws -> Void) async {
        let storeURL = env.storeURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
        let coordinator = env.migrationCoordinator
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

/// Open the system Settings app (for the iCloud sign-in / pause-reason flows).
@MainActor
func openICloudSystemSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
    }
}

/// Plan 21: iOS-side wrapper that pipes `AppEnvironment` state into the
/// cross-platform `LillistUI.ICloudSyncSettingsSection`. Renders the toggle
/// Section only; the migration modals are hosted by `ICloudSyncPage` on the
/// `SettingsDetailScreen` container (see `ICloudSyncModalsModel`).
struct ICloudSyncSection: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: ICloudSyncModalsModel
    @State private var taskCounts: TaskStore.SyncCounts?

    var body: some View {
        ICloudSyncSettingsSection(
            viewState: viewState,
            actions: actions
        )
        .task { await refreshCounts() }
        // Re-count after a sync settles so the mirrored figure tracks reality.
        .onChange(of: environment.syncMonitor.indicator) { _, _ in
            Task { await refreshCounts() }
        }
    }

    private func refreshCounts() async {
        taskCounts = try? await environment.taskStore.syncCounts()
    }

    // MARK: - View state derivation

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

    private var actions: ICloudSyncSettingsSection.Actions {
        .init(
            onToggle: { model.handleToggle($0) },
            onSyncNow: { Task { await environment.syncMonitor.retry() } },
            onOpenSystemSettings: openICloudSystemSettings,
            onPausedTap: { model.showPauseExplainer() }
        )
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        if case .available = state { return true }
        return false
    }
}
