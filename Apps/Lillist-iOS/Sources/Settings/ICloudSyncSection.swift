import SwiftUI
import LillistCore
import LillistUI
import UIKit

/// Plan 21: iOS-side wrapper that pipes `AppEnvironment` state into
/// the cross-platform `LillistUI.ICloudSyncSettingsSection`. Owns
/// the migration sheet state (choice sheet, confirmation dialog,
/// progress sheet, disable sheet, pause explainer).
struct ICloudSyncSection: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var showChoiceSheet = false
    @State private var pendingDirection: SyncMigrationConfirmationDialog.Direction?
    @State private var showDisableSheet = false
    @State private var showPauseExplainer = false
    @State private var activePhase: MigrationPhase?

    var body: some View {
        ICloudSyncSettingsSection(
            viewState: viewState,
            actions: actions
        )
        .fullScreenCover(isPresented: $showChoiceSheet) {
            SyncMigrationChoiceSheet(
                onReplaceICloud: {
                    showChoiceSheet = false
                    pendingDirection = .replaceICloud
                },
                onReplaceLocal: {
                    showChoiceSheet = false
                    pendingDirection = .replaceLocal
                },
                onCancel: { showChoiceSheet = false }
            )
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
        .fullScreenCover(item: progressBinding) { phase in
            SyncMigrationProgressSheet(
                phase: phase,
                onDismissAfterCompletion: { activePhase = nil }
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $showDisableSheet) {
            SyncDisableConfirmationSheet(
                onSyncFirst: {
                    showDisableSheet = false
                    triggerDisable(strategy: .syncFirst)
                },
                onDisableNow: {
                    showDisableSheet = false
                    triggerDisable(strategy: .now)
                },
                onCancel: { showDisableSheet = false }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPauseExplainer) {
            PauseExplainerDialog(
                reason: environment.pauseReason ?? .unknown,
                onOpenSettings: openSystemSettings,
                onDisableSync: {
                    showPauseExplainer = false
                    showDisableSheet = true
                },
                onDismiss: { showPauseExplainer = false }
            )
            .presentationDetents([.medium])
        }
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
        return .init(mode: mode, status: status, isToggleDisabled: isToggleDisabled, disabledFooter: footer)
    }

    private var actions: ICloudSyncSettingsSection.Actions {
        .init(
            onToggle: handleToggle,
            onSyncNow: { Task { await environment.syncMonitor.retry() } },
            onOpenSystemSettings: openSystemSettings,
            onPausedTap: { showPauseExplainer = true }
        )
    }

    private func handleToggle(_ on: Bool) {
        if on {
            showChoiceSheet = true
        } else {
            showDisableSheet = true
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        if case .available = state { return true }
        return false
    }

    // MARK: - Bindings

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDirection != nil },
            set: { if !$0 { pendingDirection = nil } }
        )
    }

    private var progressBinding: Binding<MigrationPhase?> {
        Binding(get: { activePhase }, set: { activePhase = $0 })
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

    // MARK: - Migration kickoff

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

    /// Drives the migration coordinator and streams phase events
    /// into `activePhase` so the progress sheet renders the live
    /// state. `storeURL` is required; in production AppEnvironment
    /// always has one — falling back to a temp path keeps the
    /// codepath defined for test fixtures.
    @MainActor
    private func runMigration(_ kickoff: @MainActor (MigrationCoordinator, URL) async throws -> Void) async {
        let storeURL = environment.storeURL
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
        let coordinator = environment.migrationCoordinator
        let phaseTask = Task { @MainActor [coordinator] in
            for await phase in coordinator.progressStream {
                activePhase = phase
            }
        }
        defer { phaseTask.cancel() }
        activePhase = .preparing
        do {
            try await kickoff(coordinator, storeURL)
        } catch {
            activePhase = .failed(reason: "\(error)")
        }
    }
}

extension MigrationPhase: @retroactive Identifiable {
    public var id: String {
        switch self {
        case .preparing: return "preparing"
        case .backingUp: return "backingUp"
        case .markingJournal: return "markingJournal"
        case .erasingICloud: return "erasingICloud"
        case .removingLocalStore: return "removingLocalStore"
        case .reconfiguringStore: return "reconfiguringStore"
        case .uploading: return "uploading"
        case .downloading: return "downloading"
        case .finalizing: return "finalizing"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}
