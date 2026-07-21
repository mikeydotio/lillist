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

    /// Issue #66: a confirmed local/mirrored gap, with guidance toward
    /// recovery — see `recoveryAdvisory(mode:status:localCount:mirroredCount:)`.
    public struct RecoveryAdvisory: Equatable, Sendable {
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

            // Issue #66: what to DO about a confirmed mirror gap — complements
            // `divergenceWarning` (which explains something looks wrong) and
            // also fires once that gap has escalated to `SyncStatusMonitor`'s
            // `.syncStalled` red badge, when recovery guidance is most needed.
            // See `recoveryAdvisory`'s doc for why this points at the existing
            // Reset tools rather than a new one-click action.
            if let advisory = recoveryAdvisory {
                VStack(alignment: .leading, spacing: 4) {
                    Text(advisory.title)
                        .font(.footnote.bold())
                    Text(advisory.message)
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

    /// Instance-side wrapper around the pure static decision function, for
    /// `body` to read directly off `viewState` — mirrors `divergenceWarning`.
    private var recoveryAdvisory: RecoveryAdvisory? {
        Self.recoveryAdvisory(
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
    ///   already surfaced), NOT `.error` (already surfaced — including the
    ///   `.syncStalled` escalation from `SyncStatusMonitor`, issue #66),
    ///   NOT `.inProgress` (mid-sync), AND the engine has completed at
    ///   least one CloudKit event *this session* (`.idle(lastSync: nil)` is
    ///   the ambiguous pre-first-event window — see `statusLine`'s doc —
    ///   and is deliberately excluded so a fresh launch never
    ///   false-positives).
    /// - There's at least one local task to mirror.
    /// - None of them have mirrored.
    ///
    /// Deliberately **not** broadened to `local > mirrored` (a partial
    /// mismatch): that shape is indistinguishable from a device that just
    /// enabled sync and is still catching up, which must stay silent. A
    /// *sustained* partial stall is instead `SyncStatusMonitor`'s job (issue
    /// #66's `consecutiveExportFailures` streak) — this function has no
    /// memory across calls to tell "still catching up" from "stuck," so it
    /// only ever fires the one unambiguous shape: nothing at all has
    /// mirrored while sync claims to be caught up.
    ///
    /// Issue #66 traced two real devices into this exact state — the
    /// message below used to name "different iCloud (CloudKit)
    /// environments" as the cause; the #66 diagnostic packages disproved
    /// that (all four devices shared one Production container/account) and
    /// found the real cause is a wedged CloudKit export, so the copy no
    /// longer guesses at a specific cause and instead points at the signals
    /// that do explain it.
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
            message: String(localized: "iCloud sync is on and your account is available, but none of your \(local) tasks have reached iCloud yet. This is expected briefly after enabling sync. If it doesn't clear up, look for a “Sync stuck” message in iCloud Sync status, or export a diagnostic package from Settings → Diagnostics for more detail.", bundle: .module)
        )
    }

    /// Issue #66: guidance toward recovery once there's a *confirmed*
    /// local/mirrored gap — a narrower trigger than `divergenceWarning`'s
    /// exact `mirrored == 0` shape (this also fires for a partial gap,
    /// `0 < mirrored < local`), and unlike `divergenceWarning` this does
    /// **not** go silent once `status` has escalated to `.error` — that's
    /// precisely when recovery help is most needed (the badge already
    /// speaks for itself, so `divergenceWarning`'s inline text would be
    /// redundant there, but this advisory is not).
    ///
    /// Deliberately does **not** offer a one-click destructive action or try
    /// to guess which of "reload from iCloud" vs. "start fresh everywhere"
    /// is safe: the two real #66 devices had the **identical** mirror-count
    /// shape (`mirrored == 0`) despite needing opposite recovery paths — one
    /// held tasks that existed nowhere else, the other held nothing unique.
    /// Only the person using the device knows which is true, so this points
    /// at the existing, already-safe Reset tools (Settings → Debug → Reset
    /// on iOS; the Advanced pane on macOS) rather than inventing a new
    /// action whose safety this function can't actually determine.
    ///
    /// `nonisolated static` for the same reason as `statusLine`: testable
    /// without a live container or the MainActor.
    nonisolated static func recoveryAdvisory(
        mode: SyncMode,
        status: SyncIndicator,
        localCount: Int?,
        mirroredCount: Int?
    ) -> RecoveryAdvisory? {
        guard mode == .iCloudSync else { return nil }
        switch status {
        case .paused, .inProgress:
            return nil
        case .idle(let lastSync):
            guard lastSync != nil else { return nil }
        case .error:
            break
        }
        guard let local = localCount, local > 0 else { return nil }
        guard let mirrored = mirroredCount, mirrored < local else { return nil }
        return RecoveryAdvisory(
            title: String(localized: "Recover this device's sync", bundle: .module),
            message: String(localized: "\(local - mirrored) of \(local) tasks on this device haven't reached iCloud. Back up your data first (Settings → Backups), then use the Reset tools: reload this device from iCloud if your other devices already have your tasks, or start fresh everywhere only if this device holds tasks that exist nowhere else.", bundle: .module)
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
