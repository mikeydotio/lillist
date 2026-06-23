import AppKit
import CoreData
import SwiftUI
import LillistCore
import Sparkle

/// Owns AppKit-bridge objects (status bar item, quick-capture panel).
/// The global hotkey monitor itself lives on ``AppEnvironment`` (Plan 11
/// Task 18) so the Quick Capture preferences pane can re-register the
/// combo at runtime; `AppDelegate.bootstrap()` still wires up its
/// `onHotkey` callback and calls `install()`.
/// Installed by `LillistApp` via `@NSApplicationDelegateAdaptor`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var quickCapturePanel: QuickCapturePanelController?
    weak var environment: AppEnvironment?

    /// Cached snapshot of the user's pinned smart filters. Read by the
    /// dock menu (which fires synchronously on right-click). Refreshed
    /// on every Core Data save by `installDockBadge()`'s observer.
    var pinnedFilterCache: [SmartFilterStore.SmartFilterRecord] = []

    /// Sparkle auto-updater. `startingUpdater: true` reads SUFeedURL and
    /// SUPublicEDKey from Info.plist and begins scheduled checks; the
    /// "Check for Updates…" menu item (LillistApp `.commands`) calls
    /// `checkForUpdates()`.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// Drives a manual update check from the app menu.
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wiring is deferred to `bootstrap()`, called from `LillistApp.task`
        // once the async `AppEnvironment.make()` has succeeded. Doing the
        // wiring here would race the environment's availability.

        // UI-test seam: pin a deterministic appearance so light/dark
        // screenshots from `Lillist-macOSUITests` don't depend on the
        // host Mac's system setting. Inert outside UI tests (no arg).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-appearance-dark") {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        } else if args.contains("--ui-test-appearance-light") {
            NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    /// Plan 19 Task 12: recover from `⌘W`-closes-only-window. SwiftUI's
    /// `WindowGroup` does not auto-reopen on Dock-icon activation;
    /// AppKit asks AppDelegate via this callback. We bounce the request
    /// through a notification so the `MainWindowReopener` modifier in
    /// `LillistApp` can invoke `@Environment(\.openWindow)`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .lillistReopenMainWindow, object: nil)
        }
        return true
    }

    func bootstrap() {
        guard let env = environment, quickCapturePanel == nil else { return }
        let panel = QuickCapturePanelController(environment: env)
        env.hotkeyMonitor.onHotkey = { panel.toggle() }
        env.hotkeyMonitor.install()
        self.quickCapturePanel = panel

        // Plan 15 Task 19: dock badge refreshes on every Core Data
        // save, and immediately on launch. Also refreshes the dock
        // menu's pinned-filter cache (Plan 15 Task 20).
        installDockBadge()

        // Plan 15 Task 23: Services provider for "Add to Lillist as task".
        // `NSUpdateDynamicServices()` registers the provider with the
        // system so the menu item appears in Services submenus.
        let servicesProvider = LillistServicesProvider(environment: env)
        NSApp.servicesProvider = servicesProvider
        self.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

        // Plan 15 Task 24: Spotlight indexing. `start()` performs an
        // initial reindex (if the format signature is stale) and
        // subscribes to Core Data save notifications for incremental
        // updates.
        let indexer = IndexingService(environment: env)
        Task { await indexer.start() }
        self.indexingService = indexer
    }

    /// Plan 15 Task 23: strong reference holder for the services
    /// provider. `NSApp.servicesProvider` is `unowned`, so without
    /// this the provider would be deallocated immediately after
    /// `bootstrap()` returns.
    private var servicesProvider: LillistServicesProvider?

    /// Plan 15 Task 24: strong reference holder for the Spotlight
    /// indexing service. The service registers a NotificationCenter
    /// observer in `start()`; the AppDelegate's lifetime keeps the
    /// observer alive for the duration of the app session.
    var indexingService: IndexingService?

    func applicationWillTerminate(_ notification: Notification) {
        environment?.hotkeyMonitor.uninstall()
        // Plan 9: delete the launch canary so the next launch knows
        // this exit was clean. Block briefly so we don't race the
        // process tear-down, but cap the wait to avoid hanging.
        if let reporter = environment?.crashReporter {
            let group = DispatchGroup()
            group.enter()
            Task {
                try? await reporter.markCleanExit()
                group.leave()
            }
            _ = group.wait(timeout: .now() + .seconds(2))
        }
    }

    // MARK: - Dock badge & menu

    /// Subscribes to Core Data save notifications and refreshes the
    /// dock badge + the pinned-filter cache on each save. Also fires
    /// an immediate refresh so the badge appears on launch (the
    /// Core Data save during bootstrap may have happened before the
    /// observer was installed).
    private func installDockBadge() {
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshDockBadge()
                await self?.refreshPinnedFilterCache()
            }
        }
        Task { @MainActor in
            await self.refreshDockBadge()
            await self.refreshPinnedFilterCache()
        }
    }

    /// Refreshes `NSApp.dockTile.badgeLabel` with the size of the
    /// "Today" smart filter's evaluate output. Clears the badge if
    /// the filter is missing or the evaluate fails.
    @MainActor
    func refreshDockBadge() async {
        guard let env = environment else { return }
        do {
            let today = try await env.smartFilterStore.fetch(byName: "Today")
            let count = try await env.smartFilterStore.evaluate(id: today.id).count
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        } catch {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    /// Refreshes the `pinnedFilterCache` snapshot consumed by
    /// `applicationDockMenu(_:)`. Filters that are not currently
    /// pinned are filtered out so the dock menu only lists items the
    /// user has explicitly elevated.
    @MainActor
    func refreshPinnedFilterCache() async {
        guard let env = environment else { return }
        let all = (try? await env.smartFilterStore.list()) ?? []
        pinnedFilterCache = all.filter(\.isPinned)
    }

    // MARK: - Dock menu (Plan 15 Task 20)

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let quick = NSMenuItem(
            title: "Quick Capture…",
            action: #selector(quickCaptureAction),
            keyEquivalent: ""
        )
        quick.target = self
        menu.addItem(quick)

        let today = NSMenuItem(
            title: "Today's Tasks…",
            action: #selector(showTodayAction),
            keyEquivalent: ""
        )
        today.target = self
        menu.addItem(today)

        // Dynamically-built pinned filters from the cache populated on
        // every Core Data save. If the cache hasn't populated yet,
        // omit the section.
        if !pinnedFilterCache.isEmpty {
            menu.addItem(.separator())
            for filter in pinnedFilterCache {
                let item = NSMenuItem(
                    title: filter.name,
                    action: #selector(selectPinnedFilter(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = filter.id
                menu.addItem(item)
            }
        }

        return menu
    }

    @objc private func quickCaptureAction() {
        quickCapturePanel?.toggle()
    }

    @objc private func showTodayAction() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == "Lillist" {
            w.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: .lillistSelectTodayFilter, object: nil)
    }

    @objc private func selectPinnedFilter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == "Lillist" {
            w.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(
            name: .lillistSelectFilter, object: nil, userInfo: ["id": id]
        )
    }
}
