import AppKit
import CoreData
import SwiftUI
import LillistCore

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wiring is deferred to `bootstrap()`, called from `LillistApp.task`
        // once the async `AppEnvironment.make()` has succeeded. Doing the
        // wiring here would race the environment's availability.
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
    }

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
}
