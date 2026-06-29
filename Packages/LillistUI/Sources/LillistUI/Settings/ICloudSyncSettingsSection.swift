import SwiftUI
import LillistCore

/// Settings/Preferences section that surfaces the user's current
/// sync mode and the controls to change it.
///
/// Plan 21 — container/presenter split:
/// `ICloudSyncSettingsSection` is *pure presentation*. The app
/// targets (iOS `ICloudSyncSection`, macOS `ICloudSyncPane`) own
/// the `AppEnvironment`-coupled state and pass everything in via
/// `ViewState` + `Actions`. Snapshot tests render this view with
/// canned `ViewState`s; no live container is required.
public struct ICloudSyncSettingsSection: View {
    public struct ViewState: Equatable, Sendable {
        public let mode: SyncMode
        public let status: SyncIndicator
        public let isToggleDisabled: Bool
        public let disabledFooter: String?
        /// Total `LillistTask` rows on this device (nil → counts not loaded yet).
        public let localTaskCount: Int?
        /// How many of those are mirrored to iCloud (have a CloudKit record id).
        public let mirroredTaskCount: Int?

        public init(
            mode: SyncMode,
            status: SyncIndicator,
            isToggleDisabled: Bool = false,
            disabledFooter: String? = nil,
            localTaskCount: Int? = nil,
            mirroredTaskCount: Int? = nil
        ) {
            self.mode = mode
            self.status = status
            self.isToggleDisabled = isToggleDisabled
            self.disabledFooter = disabledFooter
            self.localTaskCount = localTaskCount
            self.mirroredTaskCount = mirroredTaskCount
        }
    }

    public struct Actions {
        public let onToggle: (Bool) -> Void
        public let onOpenSystemSettings: () -> Void
        public let onPausedTap: () -> Void

        public init(
            onToggle: @escaping (Bool) -> Void,
            onOpenSystemSettings: @escaping () -> Void,
            onPausedTap: @escaping () -> Void = {}
        ) {
            self.onToggle = onToggle
            self.onOpenSystemSettings = onOpenSystemSettings
            self.onPausedTap = onPausedTap
        }
    }

    public let viewState: ViewState
    public let actions: Actions

    public init(viewState: ViewState, actions: Actions) {
        self.viewState = viewState
        self.actions = actions
    }

    public var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewState.mode == .iCloudSync },
                set: { actions.onToggle($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("iCloud Sync")
                        .font(.body)
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
            .disabled(viewState.isToggleDisabled)

            // No "Sync Now" control: NSPersistentCloudKitContainer mirrors
            // automatically on local edits and CloudKit pushes and exposes no
            // public force-sync, so a button could only no-op — surfacing one
            // would imply a capability the framework doesn't provide.

            // Reassurance metric: how many local tasks are mirrored to iCloud.
            // `mirrored == local` once everything is in iCloud; a gap is rows not
            // yet mirrored. Only meaningful in iCloud Sync mode.
            if viewState.mode == .iCloudSync,
               let local = viewState.localTaskCount,
               let mirrored = viewState.mirroredTaskCount {
                LabeledContent {
                    Text(verbatim: "\(mirrored) of \(local)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } label: {
                    Text("Tasks in iCloud", bundle: .module)
                }
            }
        } header: {
            HStack {
                Text("iCloud Sync")
                Spacer()
                SyncStatusBadge(indicator: viewState.status, onPausedTap: actions.onPausedTap)
            }
        } footer: {
            if let footer = viewState.disabledFooter {
                VStack(alignment: .leading, spacing: 8) {
                    Text(footer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: actions.onOpenSystemSettings)
                        .font(.footnote)
                }
            } else if viewState.mode == .iCloudSync {
                Text("Your tasks sync to your private iCloud database. Sign-out, account changes, and network outages are surfaced as a paused indicator — the app keeps working locally.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Local-only — your data stays on this device. Turn on iCloud Sync to mirror across your other Apple devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusLine: String {
        // The "…ago" formatting needs the MainActor-bound `relativeFormatter`
        // and the current time, so resolve it here and hand the pure
        // mode-aware mapping a pre-formatted string (see `statusLine(mode:…)`).
        let relativeSync: String?
        if case .idle(let last?) = viewState.status {
            relativeSync = Self.relativeFormatter.localizedString(for: last, relativeTo: Date())
        } else {
            relativeSync = nil
        }
        return Self.statusLine(mode: viewState.mode, status: viewState.status, relativeSync: relativeSync)
    }

    /// Pure mode-aware mapping from `(mode, status)` to the row subtitle.
    ///
    /// `.idle(lastSync: nil)` is ambiguous — it occurs both in local-only mode
    /// *and* in iCloud-sync mode before the first CloudKit event of the session
    /// lands (`lastSyncedAt` isn't persisted across launches). Keying the
    /// subtitle off `status` alone therefore made the row read "Off …" while the
    /// toggle was on; it must branch on `mode`. Extracted as a `nonisolated
    /// static` so non-MainActor tests can assert every branch without a live
    /// container. `relativeSync` is the caller-formatted "…ago" string for the
    /// `.idle(lastSync:)` case (nil when there's no timestamp yet), which keeps
    /// this free of the MainActor-bound formatter and makes the "Synced …"
    /// branch deterministically testable.
    nonisolated static func statusLine(
        mode: SyncMode,
        status: SyncIndicator,
        relativeSync: String?
    ) -> String {
        // Local-only is the only state where "Off" is truthful.
        guard mode == .iCloudSync else {
            return String(localized: "Off — your data stays on this device", bundle: .module)
        }
        switch status {
        case .idle:
            if let relativeSync {
                return String(localized: "Synced \(relativeSync)", bundle: .module)
            }
            return String(localized: "On — sync is active", bundle: .module)
        case .inProgress:
            return String(localized: "Syncing…", bundle: .module)
        case .error(let msg, _):
            return String(localized: "Sync error: \(msg)", bundle: .module)
        case .paused:
            return String(localized: "Sync paused — iCloud unavailable", bundle: .module)
        }
    }

    private var statusColor: Color {
        switch viewState.status {
        case .error: return .red
        case .paused: return .yellow
        default: return .secondary
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()
}
