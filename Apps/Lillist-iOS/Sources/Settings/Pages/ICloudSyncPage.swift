import SwiftUI
import LillistCore
import LillistUI

/// Settings → iCloud Sync. Wraps the env-coupled `ICloudSyncSection` (the sync
/// toggle) in the shared sub-page chrome and **hosts the migration modals here**,
/// on the `SettingsDetailScreen` container — not inside the section's `Section`.
/// A `.sheet` attached to Form-row content inside this pushed
/// nav-destination-in-a-sheet present-then-dismisses and nukes the whole Settings
/// sheet (see `ICloudSyncModalsModel`).
struct ICloudSyncPage: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model = ICloudSyncModalsModel()

    var body: some View {
        SettingsDetailScreen("iCloud Sync") {
            ICloudSyncSection(model: model)
        }
        // The confirmation dialog is a distinct presentation kind and coexists
        // safely with one sheet; the choice → confirm handoff is unchanged.
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible,
            actions: {
                Button("Replace", role: .destructive) { model.confirmReplace(environment) }
                Button("Cancel", role: .cancel) { model.pendingDirection = nil }
            },
            message: { Text(confirmationMessage) }
        )
        .sheet(item: $model.route) { sheet in
            switch sheet {
            case .choice:
                SyncMigrationChoiceSheet(
                    onReplaceICloud: { model.route = nil; model.pendingDirection = .replaceICloud },
                    onReplaceLocal: { model.route = nil; model.pendingDirection = .replaceLocal },
                    onCancel: { model.route = nil }
                )
                .presentationDetents([.large])
            case .disable:
                SyncDisableConfirmationSheet(
                    // `triggerDisable` → `runMigration` swaps `route` straight to
                    // `.progress`, so the dismiss-one-present-another conflict
                    // that used to nuke Settings can't happen.
                    onSyncFirst: { model.triggerDisable(strategy: .syncFirst, environment) },
                    onDisableNow: { model.triggerDisable(strategy: .now, environment) },
                    onCancel: { model.route = nil }
                )
                .presentationDetents([.medium])
            case .pauseExplainer:
                PauseExplainerDialog(
                    reason: environment.pauseReason ?? .unknown,
                    onOpenSettings: openICloudSystemSettings,
                    onDisableSync: { model.route = .disable },
                    onDismiss: { model.route = nil }
                )
                .presentationDetents([.medium])
            case .progress(let phase):
                SyncMigrationProgressSheet(
                    phase: phase,
                    onDismissAfterCompletion: { model.route = nil }
                )
                .presentationDetents([.large])
                .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Confirmation dialog text

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { model.pendingDirection != nil },
            set: { if !$0 { model.pendingDirection = nil } }
        )
    }

    private var confirmationTitle: String {
        switch model.pendingDirection {
        case .replaceICloud: return String(localized: "Replace iCloud with This Device?")
        case .replaceLocal: return String(localized: "Replace This Device with iCloud?")
        case nil: return ""
        }
    }

    private var confirmationMessage: String {
        switch model.pendingDirection {
        case .replaceICloud:
            return String(localized: "This permanently replaces iCloud's data with what's on this device. Other devices syncing this iCloud account will see this change. This cannot be undone.")
        case .replaceLocal:
            return String(localized: "This permanently replaces this device's data with what's in iCloud. This cannot be undone.")
        case nil: return ""
        }
    }
}
