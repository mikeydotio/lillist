import ArgumentParser
import Foundation
import LillistCore

// MARK: Crash-reporting lifecycle (design Section 8; Plan 9 Task 15)

private let cliReporter: CrashReporter = CLICanaryLifecycle.makeReporter()

// Surface a notice on TTY if the previous run did not exit cleanly,
// then write a fresh canary for this run. We block the main work
// on this so the canary is guaranteed to exist before any work runs.
await CLICanaryLifecycle.bootstrap(reporter: cliReporter)

// Best-effort clean-exit hooks. Signal handlers can only do
// sync-safe work, so they call the sync deleter; the normal-exit
// hook uses the async path and a DispatchGroup to wait briefly.
atexit_b {
    CLICanaryLifecycle.teardown(reporter: cliReporter)
}
signal(SIGTERM) { _ in
    CLICanaryLifecycle.teardownSync()
    Foundation.exit(143)
}
signal(SIGINT) { _ in
    CLICanaryLifecycle.teardownSync()
    Foundation.exit(130)
}

// MARK: argument parser dispatch
await Lillist.runWithExitCodes()
