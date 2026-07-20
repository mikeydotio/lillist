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

    /// Issue #54: sync claims to be on and healthy, but nothing is actually
    /// reaching iCloud — see `divergenceWarning(mode:status:localCount:mirroredCount:)`.
    public struct DivergenceWarning: Equatable, Sendable {
        public let title: String
        public let message: String

        public init(title: String, message: String) {
            self.title = title
            self.message = message
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

            // Issue #54: the loud counterpart to the reassurance metric above —
            // fires only for the narrow "claims active, mirrors nothing" anomaly
            // (see `divergenceWarning`'s doc). Functional cautionAmber, per the
            // Rainbow Logic house rule that color is functional, never decorative.
            if let warning = divergenceWarning {
                VStack(alignment: .leading, spacing: 4) {
                    Text(warning.title)
                        .font(.footnote.bold())
                    Text(warning.message)
                        .font(.footnote)
                }
                .foregroundStyle(RainbowPalette.cautionAmber.ink)
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

    /// Instance-side wrapper around the pure static decision function, for
    /// `body` to read directly off `viewState` — mirrors `statusLine`.
    private var divergenceWarning: DivergenceWarning? {
        Self.divergenceWarning(
            mode: viewState.mode,
            status: viewState.status,
            localCount: viewState.localTaskCount,
            mirroredCount: viewState.mirroredTaskCount
        )
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

    /// Issue #54: four devices on the same account diverged because
    /// "sync is active" and "0 of N tasks mirrored" can both be true at
    /// once, and nothing said so. This is a loud, low-false-positive guard
    /// for exactly that anomaly — not a general health check.
    ///
    /// Fires only when **every** condition holds:
    /// - iCloud Sync is the selected mode.
    /// - `status` is `.idle(lastSync: .some)` — i.e. NOT `.paused` (account
    ///   already surfaced), NOT `.error` (already surfaced), NOT
    ///   `.inProgress` (mid-sync), AND the engine has completed at least one
    ///   CloudKit event *this session* (`.idle(lastSync: nil)` is the
    ///   ambiguous pre-first-event window — see `statusLine`'s doc — and is
    ///   deliberately excluded so a fresh launch never false-positives).
    /// - There's at least one local task to mirror.
    /// - None of them have mirrored.
    ///
    /// `nonisolated static` for the same reason as `statusLine`: testable
    /// without a live container or the MainActor.
    nonisolated static func divergenceWarning(
        mode: SyncMode,
        status: SyncIndicator,
        localCount: Int?,
        mirroredCount: Int?
    ) -> DivergenceWarning? {
        guard mode == .iCloudSync else { return nil }
        guard case .idle(.some) = status else { return nil }
        guard let local = localCount, local > 0 else { return nil }
        guard let mirrored = mirroredCount, mirrored == 0 else { return nil }
        return DivergenceWarning(
            title: String(localized: "This device may not be sharing tasks", bundle: .module),
            message: String(localized: "iCloud sync is on and your account is available, but none of your \(local) tasks have reached iCloud yet. This can happen when your devices are signed into different iCloud (CloudKit) environments. Export a diagnostic package from each device and compare the CloudKit Environment shown in Diagnostics.", bundle: .module)
        )
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
