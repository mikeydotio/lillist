import SwiftUI
import LillistCore
import LillistUI

/// Renders the wrapped main-window content at a fixed fraction of its natural
/// size so the macOS main window — which reuses the iOS single-column surface —
/// reads at a comfortable Mac density rather than oversized.
///
/// A bare `.scaleEffect` shrinks the rendered pixels but leaves the layout
/// footprint unchanged, so the content would draw small in one corner. Instead
/// we lay the content out at `1 / scale` of the available window space and then
/// scale that down by `scale`, which makes the content *reflow* denser while
/// still filling the same window. Hit-testing maps correctly through the
/// transform; the only cost is a slightly softer text raster at non-integral
/// scales — accepted here in exchange for not forking the shared design tokens
/// (`LillistSpacing`/`LillistTypography`), which iOS also consumes.
private struct ScaledWindowContent: ViewModifier {
    /// The render scale, e.g. `0.75` for "about 25% smaller".
    let scale: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width / scale,
                       height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

@main
struct LillistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment?
    @State private var loadError: String?
    @State private var statusBarItemVisible = true
    /// Drives the in-window unified editor's new-capture trigger from both
    /// `LillistCommands` (⌘N) and the bottom-trailing FAB.
    @State private var isQuickCapturePresented = false
    /// macOS main-window sort selection, persisted per-machine. Distinct
    /// key from iOS's `lillist.ios.sort` so the platforms don't collide.
    @AppStorage("lillist.macos.sort") private var sortRaw: String = TasksSort.personalized.rawValue

    /// macOS main-window render scale. The shared iOS single-column surface
    /// reads oversized on the Mac, so the main window draws at 75% (≈25%
    /// smaller / denser). Tunable in one place; see `ScaledWindowContent`.
    private let macUIScale: CGFloat = 0.75

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
    }

    var body: some Scene {
        WindowGroup("Lillist", id: "main") {
            content
                // Render the shared iOS single-column surface ~25% smaller on
                // macOS (denser), keeping the same window canvas. Applied
                // before `.frame` so the window sizing below governs the space
                // the scaled content reflows into.
                .modifier(ScaledWindowContent(scale: macUIScale))
                // Narrow, iPhone-width default; freely resizable with a
                // ~360 floor and no ceiling (`.contentMinSize`). The main
                // window is now the shared iOS single-column surface.
                .frame(minWidth: 360, idealWidth: 420, minHeight: 480, idealHeight: 720)
                .environment(\.isQuickCapturePresentedBinding, $isQuickCapturePresented)
                .environment(\.sortBinding, sortBinding)
                .task { await loadEnvironmentIfNeeded() }
                .onOpenURL { handleDeepLink($0) }
                .modifier(MainWindowReopener())
        }
        .defaultSize(width: 420, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            // Sparkle "Check for Updates…" in the app menu, just below
            // "About Lillist". Always available (not gated on environment).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    appDelegate.checkForUpdates()
                }
            }
            if environment != nil {
                LillistCommands(isQuickCapturePresented: $isQuickCapturePresented)
            }
        }

        // Plan 10: Preferences scene. SwiftUI's `Settings { ... }`
        // produces the standard ⌘, window with native tab styling.
        Settings {
            if let environment {
                PreferencesWindow()
                    .environment(environment)
            } else {
                // Plan 15 Task 26: the loaded panes self-size via
                // `.fixedSize()`, so the placeholder also self-sizes
                // (just paddding around the spinner). Don't lock to
                // the old 520×420 — that was the only artifact pinning
                // a square window even when only one tab was tall.
                ProgressView("Loading…")
                    .padding()
            }
        }

        // Plan 15 Task 9: SwiftUI MenuBarExtra scene replaces the
        // AppKit-bridge StatusBarController. `isInserted:` is driven
        // by `PreferencesStore.statusBarItemVisible` and primed in
        // `loadEnvironmentIfNeeded()`; flipping the toggle in
        // Preferences adds/removes the scene at runtime. The scene
        // is declared unconditionally (SceneBuilder's type-checker
        // handles optional Scenes poorly); MenuBarExtraScene itself
        // takes an optional `AppEnvironment?` and renders a
        // placeholder while it's still loading.
        MenuBarExtraScene(
            isInserted: $statusBarItemVisible,
            environment: environment,
            onQuickCapture: triggerQuickCapture
        )
    }

    private func triggerQuickCapture() {
        appDelegate.quickCapturePanel?.toggle()
    }

    /// Route an inbound `lillist://` deep link (from the desktop widget). Quick
    /// Capture opens the global capture panel; a filter link focuses that filter
    /// and a task link opens that task via the environment (drained by
    /// `MacTasksView`). The main window is reopened first so a `MacTasksView`
    /// exists to consume the handoff even if it was closed (⌘W).
    private func handleDeepLink(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .quickCapture:
            triggerQuickCapture()
        case .filter(let id):
            NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
            environment?.pendingSelectedFilterID = id
        case .task(let id):
            NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
            environment?.pendingOpenTaskID = id
        }
    }

    @ViewBuilder
    private var content: some View {
        if let environment {
            CrashReporterHost(
                reporter: environment.crashReporter,
                buildVersion: environment.buildVersion,
                osVersion: environment.osVersion,
                deviceModel: environment.deviceModel,
                crashPromptsEnabled: environment.crashPromptsEnabled
            ) {
                MacTasksView()
                    .environment(environment)
                    .modifier(OnboardingPresentationModifier(environment: environment))
            }
        } else if let loadError {
            EmptyStateView(
                title: "Could not load Lillist",
                message: loadError,
                systemImage: "exclamationmark.triangle"
            )
        } else {
            ProgressView("Loading Lillist…")
        }
    }

    private func loadEnvironmentIfNeeded() async {
        guard environment == nil, loadError == nil else { return }
        do {
            if ProcessInfo.processInfo.arguments.contains("--ui-test-reset-store") {
                await Self.uiTestResetState()
            }
            let env = try await AppEnvironment.make()
            // UI-test seam: install the default filters + seed demo content
            // BEFORE the first render so the main window shows seeded rows
            // on first paint.
            if ProcessInfo.processInfo.arguments.contains("--ui-test-seed-demo") {
                try? await env.defaultsInstaller.installIfNeeded()
                await Self.uiTestSeedDemo(env)
            }
            environment = env
            appDelegate.environment = env
            appDelegate.bootstrap()
            await env.bootstrap()
            // Plan 19 Task 10: sole install path — runs on every launch
            // (idempotent by name). OnboardingSheet used to call this too
            // but that was redundant: a user who quits mid-onboarding
            // still gets defaults the next launch through this code path.
            try? await env.defaultsInstaller.installIfNeeded()
            // Plan 15 Task 9: prime the menu-bar visibility binding from
            // user prefs so the MenuBarExtra scene inserts (or not) on
            // first launch matching the saved setting.
            if let prefs = try? await env.preferencesStore.read() {
                statusBarItemVisible = prefs.statusBarItemVisible
            }
            // UI-test seam: present the global quick-capture panel. The real
            // ⌃⌥Space hotkey is a CGEvent monitor XCUITest can't synthesize,
            // so the test asks for the panel directly. The panel is created
            // in `appDelegate.bootstrap()` above.
            if ProcessInfo.processInfo.arguments.contains("--ui-test-show-quick-capture") {
                appDelegate.quickCapturePanel?.toggle()
            }
        } catch {
            loadError = "\(error)"
        }
    }

    // MARK: - UI-test seams
    //
    // Mirror the iOS app's launch-argument hooks (see the iOS `LillistApp`).
    // Each is gated on an explicit `--ui-test-*` argument that production
    // launches never pass, so these paths are inert outside XCUITest. They
    // let `Lillist-macOSUITests` drive the real `AppEnvironment` against a
    // known-clean, deterministically-seeded store and capture screenshots of
    // live (glass-rendered) surfaces — the only way to verify macOS glass,
    // which is not offscreen-snapshottable.

    /// Wipe the on-disk store + App Group defaults and pre-mark onboarding
    /// complete in LocalOnly mode, so a UI-test run starts from a known
    /// state without an iCloud account. Invoked only under
    /// `--ui-test-reset-store`. Production code paths never call this.
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
        // Per-machine UI state lives in UserDefaults.standard. The
        // single-column main window persists only the sort selection
        // (`lillist.macos.sort`); clear it so a fresh run starts neutral.
        let standard = UserDefaults.standard
        for key in ["lillist.macos.sort"] {
            standard.removeObject(forKey: key)
        }
        await DevicePreferencesStore(appGroupID: AppEnvironment.appGroupID)
            .setHasCompletedOnboarding(true)
        await SyncModeStore(appGroupID: AppEnvironment.appGroupID).setMode(.localOnly)
        UserDefaults(suiteName: AppEnvironment.appGroupID)?.synchronize()
    }

    /// Seed deterministic demo content (tasks spanning every status, two
    /// tags, one subtask) so screenshots aren't empty. Invoked only under
    /// `--ui-test-seed-demo` (paired with `--ui-test-reset-store`). The
    /// default smart filters are installed separately by
    /// `defaultsInstaller.installIfNeeded()`.
    private static func uiTestSeedDemo(_ env: AppEnvironment) async {
        do {
            let work = try await env.tagStore.findOrCreate(name: "Work", tintColor: "#2E90FA")
            let home = try await env.tagStore.findOrCreate(name: "Home", tintColor: "#34C25A")

            let roadmap = try await env.taskStore.create(title: "Draft Q3 roadmap")
            try await env.taskStore.assignTag(taskID: roadmap, tagID: work)

            let review = try await env.taskStore.create(title: "Review pull requests")
            try await env.taskStore.assignTag(taskID: review, tagID: work)
            try await env.taskStore.transition(id: review, to: .started)

            let signoff = try await env.taskStore.create(title: "Waiting on design sign-off")
            try await env.taskStore.transition(id: signoff, to: .blocked)

            let dentist = try await env.taskStore.create(title: "Book dentist appointment")
            try await env.taskStore.assignTag(taskID: dentist, tagID: home)

            let passport = try await env.taskStore.create(title: "Renew passport")
            _ = try await env.taskStore.create(title: "Gather supporting documents", parent: passport)
            try await env.taskStore.transition(id: passport, to: .closed)
        } catch {
            // Best-effort seed; never block launch on a seeding failure.
        }
    }
}

/// Plan 21 onboarding presentation (macOS): drives a one-time
/// evaluation in `.task`, then layers either the onboarding sheet
/// or the cross-platform `ICloudUnavailableScreen` on top of the
/// main window content. Replaces the old blocking
/// `ICloudRequiredView` — the app is no longer gated behind iCloud.
///
/// Also surfaces `SyncMigrationRecoverySheet` if a crashed previous
/// migration left the journal non-idle.
private struct OnboardingPresentationModifier: ViewModifier {
    let environment: AppEnvironment

    @State private var didEvaluate = false
    /// One presentation slot for the three mutually-exclusive launch gates.
    /// Three stacked `.sheet` modifiers let the iCloud-unavailable → onboarding
    /// handoff (dismiss-one-present-another) clobber a sheet; a single
    /// `.sheet(item:)` makes every transition a clean slot swap.
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
            .sheet(item: $launch) { sheet in
                switch sheet {
                case .iCloudUnavailable:
                    ICloudUnavailableScreen {
                        Task {
                            await environment.syncModeStore.setMode(.localOnly)
                            try? await environment.persistenceHost.reconfigure(to: .localOnly)
                            launch = .onboarding
                        }
                    }
                    .interactiveDismissDisabled(true)
                    .frame(width: 520, height: 380)
                case .onboarding:
                    OnboardingSheet(
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
                            try? environment.migrationJournalStore.clear()
                            launch = nil
                        }
                    )
                    .interactiveDismissDisabled(true)
                    .frame(width: 520, height: 380)
                }
            }
    }

    private func evaluate() async {
        // UI-test seam: force the onboarding sheet up so it can be captured,
        // regardless of stored completion state (the reset seam marks
        // onboarding complete, which would otherwise suppress it).
        if ProcessInfo.processInfo.arguments.contains("--ui-test-force-onboarding") {
            launch = .onboarding
            return
        }
        // UI-test seam: keep onboarding / iCloud-unavailable / recovery
        // sheets down so the test sees the bare main window. Mirrors iOS.
        if ProcessInfo.processInfo.arguments.contains("--ui-test-bypass-gates") {
            return
        }
        let journal = try? environment.migrationJournalStore.read()
        if let journal, journal.isInFlight {
            // Only offer recovery for a *stale* (crashed) migration. A
            // fresh in-flight journal belongs to a migration that may still
            // be completing in another process/launch; surfacing recovery
            // would race it. The MigrationGate keeps blocking new work
            // either way.
            if journal.isStale() {
                launch = .recovery(journal)
            }
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
    public var id: String {
        "\(state.rawValue)-\(operation?.rawValue ?? "")-\(startedAt?.timeIntervalSince1970 ?? 0)"
    }
}

/// Plan 19 Task 12: re-spawn the main window when the user closes the
/// only window with `⌘W` and then clicks the Dock icon (or hits the
/// "Show Main Window" item in the menu-bar popover). Both paths post
/// `.lillistReopenMainWindow`; this modifier grabs `openWindow` from
/// the SwiftUI environment and reopens the `WindowGroup(id: "main")`.
private struct MainWindowReopener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .lillistReopenMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}
