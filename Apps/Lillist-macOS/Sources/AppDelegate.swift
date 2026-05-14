import AppKit
import SwiftUI

/// Owns AppKit-bridge objects (status bar item, global hotkey monitor, quick-capture panel).
/// Installed by `LillistApp` via `@NSApplicationDelegateAdaptor`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var hotkeyMonitor: GlobalHotkeyMonitor?
    var quickCapturePanel: QuickCapturePanelController?
    weak var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Wiring is deferred to `bootstrap()`, called from `LillistApp.task`
        // once the async `AppEnvironment.make()` has succeeded. Doing the
        // wiring here would race the environment's availability.
    }

    func bootstrap() {
        guard let env = environment, statusBarController == nil else { return }
        let panel = QuickCapturePanelController(environment: env)
        let hk = GlobalHotkeyMonitor()
        hk.onHotkey = { panel.toggle() }
        hk.install()
        self.quickCapturePanel = panel
        self.hotkeyMonitor = hk
        self.statusBarController = StatusBarController(
            environment: env,
            onQuickCapture: { panel.toggle() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyMonitor?.uninstall()
        statusBarController?.uninstall()
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
}
