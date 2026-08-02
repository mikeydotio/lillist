import SwiftUI
import LillistCore
import LillistUI
import BackgroundTasks

@main
struct LillistApp: App {
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var isQuickCapturePresented = false

    /// Persisted sort selection for the single primary `TasksView`.
    /// Default is `.personalized` (user-controlled drag order). Stored
    /// as `rawValue`; the `Binding<TasksSort>` is computed over it so
    /// downstream views read/write a typed value.
    @AppStorage("lillist.ios.sort")
    private var sortRaw: String = TasksSort.personalized.rawValue

    private var sortBinding: Binding<TasksSort> {
        Binding(
            get: { TasksSort(rawValue: sortRaw) ?? .personalized },
            set: { sortRaw = $0.rawValue }
        )
    }

    init() {
        // Register the bundled Plus Jakarta Sans faces before the first
        // frame renders, so LillistTypography never falls back to system
        // fonts for a flash. (Registration is also lazy via the
        // typography factory; this call just front-loads it.)
        LillistFonts.registerIfNeeded()

        // Persist-6: register the background trash-purge handler before
        // launch completes (BGTaskScheduler requires registration during
        // app init). The handler builds a short-lived AppEnvironment so it
        // can run without the foreground SwiftUI environment being alive.
        //
        // The launch-handler closure is @Sendable / non-isolated (it does
        // NOT inherit LillistApp's implicit @MainActor), and BGTask is not
        // Sendable. So we: wire expirationHandler first; run the MainActor
        // work on an explicit `Task { @MainActor in … }`; and complete the
        // task back on the closure's own (non-isolated) thread using only
        // the Bool that crosses the actor hop — never the BGTask itself.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundPurgeSchedule.taskIdentifier,
            using: nil
        ) { task in
            // `expirationHandler` and `setTaskCompleted` are on the BGTask
            // base class, so no BGProcessingTask cast is needed here.
            let work = Task { @MainActor in
                // Hop to the MainActor explicitly: both AppEnvironment.make()
                // and env.runBackgroundPurge() are @MainActor-isolated.
                let ok = await Self.runBackgroundPurge()
                Self.scheduleBackgroundPurge()
                return ok
            }
            // Set expiration before awaiting `work` so an early expiration
            // can cancel the in-flight purge. `task` stays on this
            // non-isolated thread; only the Bool result crosses the hop.
            task.expirationHandler = { work.cancel() }
            Task {
                // `work` is a non-throwing `Task<Bool, Never>`; awaiting its
                // value never throws (a cancelled run returns `false` from
                // `runBackgroundPurge()`), so no `try?` is needed here.
                let ok = await work.value
                task.setTaskCompleted(success: ok)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            content
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.sortBinding, sortBinding)
                .task { await loadEnvironmentIfNeeded() }
                .onOpenURL { handleDeepLink($0) }
        }
        .commands {
            LillistCommands(isQuickCapturePresented: $isQuickCapturePresented)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let environment {
            CrashReporterHost(
                reporter: environment.crashReporter,
                mailTransport: environment.mailTransport,
                buildVersion: environment.buildVersion,
                osVersion: environment.osVersion,
                deviceModel: environment.deviceModel,
                crashPromptsEnabled: environment.crashPromptsEnabled
            ) {
                RootShell()
                    .environment(environment)
                    .modifier(OnboardingPresentationModifier(environment: environment))
                    .timeZoneChangeAlert(
                        offer: Binding(
                            get: { environment.pendingTimeZoneOffer },
                            set: { environment.pendingTimeZoneOffer = $0 }
                        ),
                        onReschedule: { _ in Task { await environment.acceptTimeZoneChange() } },
                        onKeep: { _ in Task { await environment.declineTimeZoneChange() } }
                    )
            }
        } else if let loadError {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text("Could not load Lillist")
                    .font(.headline)
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            ProgressView("Loading Lillist…")
        }
    }

    /// Route an inbound `lillist://` deep link (from the widget). Quick Capture
    /// opens the capture sheet; filter and task links hand the id to `TasksView`
    /// via the environment (which focuses the filter / opens the task).
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .quickCapture:
            isQuickCapturePresented = true
        case .filter(let id):
            environment?.pendingSelectedFilterID = id
        case .task(let id):
            environment?.pendingOpenTaskID = id
        }
    }

    private func loadEnvironmentIfNeeded() async {
        guard environment == nil, loadError == nil else { return }
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-store") {
                await Self.uiTestResetState()
            }
            let env = try await AppEnvironment.make()
            await env.bootstrap()
            try? await env.defaultsInstaller.installIfNeeded()
            // UI-test seam: seed one task with a long notes body BEFORE the
            // first render, so the full editor's card is tall enough that
            // tapping "+ Tag" (which raises the keyboard) shrinks the offered
            // height and makes the wrap card scroll in place. `TaskTapOpenUITests`
            // needs that keyboard-driven boundary crossing to exercise the
            // tag-field survival contract; a title-only task never reaches it.
            // Paired with `--ui-test-reset-store`; inert outside XCUITest.
            if ProcessInfo.processInfo.arguments.contains("--ui-test-seed-fat-notes") {
                await Self.uiTestSeedFatTask(env)
            }
            environment = env
            Self.scheduleBackgroundPurge()
        } catch {
            loadError = "\(error)"
        }
    }

    /// UI-test seam: wipe on-disk store + App Group defaults and pre-mark
    /// onboarding complete in LocalOnly mode. Only invoked when the host is
    /// launched with the `--ui-test-reset-store` argument by
    /// `Lillist-iOSUITests`. Production code paths never call this.
    private static func uiTestResetState() async {
        let fm = FileManager.default
        if let group = fm.containerURL(
            forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupID
        ) {
            try? fm.removeItem(at: group.appendingPathComponent("Lillist", isDirectory: true))
            try? fm.removeItem(at: group.appendingPathComponent("launch.canary"))
        }
        if let appSupport = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            try? fm.removeItem(at: appSupport.appendingPathComponent("Lillist", isDirectory: true))
        }
        if let groupDefaults = UserDefaults(suiteName: AppEnvironment.appGroupID) {
            groupDefaults.removePersistentDomain(forName: AppEnvironment.appGroupID)
            groupDefaults.synchronize()
        }
        // State-restoration keys live in UserDefaults.standard. Clear
        // both the old (pre-UI-refresh) section/path keys and the new
        // sort key so a fresh UI-test run starts clean.
        let standard = UserDefaults.standard
        standard.removeObject(forKey: "lillist.ios.section")
        standard.removeObject(forKey: "lillist.ios.filters.path")
        standard.removeObject(forKey: "lillist.ios.sort")
        await DevicePreferencesStore(appGroupID: AppEnvironment.appGroupID)
            .setHasCompletedOnboarding(true)
        await SyncModeStore(appGroupID: AppEnvironment.appGroupID).setMode(.localOnly)
        UserDefaults(suiteName: AppEnvironment.appGroupID)?.synchronize()
    }

    /// UI-test seam: seed a single task whose notes body is long enough to
    /// drive the full editor's content-hugging notes field (`.lineLimit(2...8)`)
    /// toward its scroll cap, making the detail card tall. The card then fits
    /// the offered height with the keyboard down but overflows it once "+ Tag"
    /// raises the keyboard, so the wrap card scrolls in place — the exact
    /// keyboard-driven boundary crossing `TaskTapOpenUITests` must reach. Title
    /// and body come from the shared `UITestSeedContent` so the app-hosted
    /// `GlassSnapshotTests` probes measure the same card. Only invoked under the
    /// `--ui-test-seed-fat-notes` argument; production code paths never call it.
    private static func uiTestSeedFatTask(_ env: AppEnvironment) async {
        // Best-effort seed; never block launch on a seeding failure.
        _ = try? await env.taskStore.create(
            title: UITestSeedContent.fatNotesTaskTitle,
            notes: UITestSeedContent.fatNotesBody()
        )
    }

    /// Build a fresh environment, run the purge, tear it down. Used only by
    /// the background task — the foreground env is owned by `@State`.
    private static func runBackgroundPurge() async -> Bool {
        guard let env = try? await AppEnvironment.make() else { return false }
        return await env.runBackgroundPurge()
    }

    /// Submit the next background-processing request. Safe to call after
    /// every run; the scheduler coalesces duplicate identifiers.
    static func scheduleBackgroundPurge() {
        let request = BGProcessingTaskRequest(identifier: BackgroundPurgeSchedule.taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: BackgroundPurgeSchedule.earliestBeginInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// iOS counterpart of macOS's onboarding presentation modifier.
/// Drives a one-time evaluation on first .task fire, then layers
/// either OnboardingScreen or the new ICloudUnavailableScreen on top
/// of the root tab shell. Plan 21 replaces the blocking
/// ICloudRequiredScreen — the app is never gated behind iCloud now;
/// the unavailable screen is informational and the user continues
/// into LocalOnly.
///
/// The modifier also surfaces `SyncMigrationRecoverySheet` when a
/// crashed previous migration left the `MigrationJournal` non-idle.
private struct OnboardingPresentationModifier: ViewModifier {
    let environment: AppEnvironment

    @State private var didEvaluate = false
    /// One presentation slot for the three mutually-exclusive launch gates.
    /// Three stacked `.fullScreenCover` modifiers let the iCloud-unavailable →
    /// onboarding handoff (dismiss-one-present-another) clobber a cover; a single
    /// `.fullScreenCover(item:)` makes every transition a clean slot swap.
    @State private var launch: LaunchSheet?

    private enum LaunchSheet: Identifiable {
        case iCloudUnavailable
        case onboarding
        case recovery(MigrationJournal)
        var id: String {
            switch self {
            case .iCloudUnavailable: return "iCloudUnavailable"
            case .onboarding: return "onboarding"
            // The journal's id fingerprints the failure, so a retry re-presents.
            case .recovery(let journal): return "recovery-\(journal.id)"
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .task {
                guard !didEvaluate else { return }
                didEvaluate = true
                await evaluate()
            }
            .fullScreenCover(item: $launch) { sheet in
                switch sheet {
                case .iCloudUnavailable:
                    ICloudUnavailableScreen {
                        Task {
                            // data-sync-hardening S17: this is semantically a
                            // disableNow transition (iCloudSync -> localOnly,
                            // immediate — there's no iCloud account to sync
                            // with) that happens to run before onboarding.
                            // Route it through the coordinator instead of a
                            // raw setMode+reconfigure pair: journaled,
                            // gated, notification-cancelled, and correctly
                            // ordered (reconfigure before setMode, matching
                            // every other transition — the direct calls this
                            // replaced ran them backwards).
                            let url = environment.storeURL
                                ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
                            do {
                                try await environment.migrationCoordinator.beginDisable(strategy: .now, storeURL: url)
                                launch = .onboarding
                            } catch {
                                // Surface the coordinator's own recovery path
                                // rather than silently proceeding to
                                // onboarding on an inconsistent store — the
                                // coordinator already left a .failed journal
                                // entry for this failure.
                                if let journal = try? environment.migrationJournalStore.read(), journal.isInFlight {
                                    launch = .recovery(journal)
                                } else {
                                    launch = nil
                                }
                            }
                        }
                    }
                    .interactiveDismissDisabled(true)
                case .onboarding:
                    OnboardingScreen(
                        onboardingState: environment.onboardingState,
                        installer: environment.defaultsInstaller,
                        notificationPermissions: environment.notificationPermissions,
                        onCompleted: { launch = nil }
                    )
                    .interactiveDismissDisabled(true)
                case .recovery(let journal):
                    SyncMigrationRecoverySheet(
                        journal: journal,
                        onRestoreFromBackup: {
                            Task {
                                let url = environment.storeURL
                                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
                                try? await environment.migrationCoordinator.restoreFromBackup(targetURL: url)
                                launch = nil
                            }
                        },
                        onTryAgain: {
                            Task {
                                let url = environment.storeURL
                                    ?? FileManager.default.temporaryDirectory.appendingPathComponent("Lillist.sqlite")
                                do {
                                    // S19: actually re-runs the failed
                                    // operation from the top — the prior
                                    // version only cleared the journal and
                                    // dismissed, never retrying anything.
                                    try await environment.migrationCoordinator.retryFailedOperation(from: journal, storeURL: url)
                                    launch = nil
                                } catch {
                                    // Mirrors the ICloudUnavailableScreen
                                    // catch below: surface the coordinator's
                                    // own fresh recovery state rather than
                                    // silently proceeding on an
                                    // inconsistent store.
                                    if let refreshed = try? environment.migrationJournalStore.read(), refreshed.isInFlight {
                                        launch = .recovery(refreshed)
                                    } else {
                                        launch = nil
                                    }
                                }
                            }
                        }
                    )
                    .interactiveDismissDisabled(true)
                }
            }
    }

    private func evaluate() async {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-bypass-gates") {
            return
        }
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            // data-sync-hardening S16: show the recovery path immediately
            // for ANY in-flight journal, not just a stale one. Only the
            // main app ever runs MigrationCoordinator — no extension calls
            // beginEnable/beginDisable — so a non-idle journal found at
            // launch can never belong to a migration genuinely still
            // completing in another live process; it's always a previous,
            // now-dead process's leftover state. MigrationGate already
            // blocks every extension unconditionally on any non-idle
            // journal — leaving the user with no explanation for up to
            // 600+ seconds (the old staleness threshold) was the bug.
            launch = .recovery(journal)
            return
        }
        let done = await environment.onboardingState.hasCompletedOnboarding()
        guard !done else { return }
        if isAvailable(environment.accountState) {
            await environment.syncModeStore.setMode(.iCloudSync)
            launch = .onboarding
        } else {
            launch = .iCloudUnavailable
        }
    }

    private func isAvailable(_ state: iCloudAccountState) -> Bool {
        switch state {
        case .available: return true
        case .noAccount, .restricted, .accountChanged: return false
        }
    }
}

extension MigrationJournal: @retroactive Identifiable {
    /// Identifier the SwiftUI sheet binding needs. The journal is a
    /// singleton on disk so any non-empty identifier suffices; the
    /// failure-reason fingerprint changes between attempts which
    /// keeps the sheet re-presenting when the user retries.
    public var id: String {
        "\(state.rawValue)-\(operation?.rawValue ?? "")-\(startedAt?.timeIntervalSince1970 ?? 0)"
    }
}
