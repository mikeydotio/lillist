import Foundation
import MetricKit
import LillistCore

/// Subscribes to MetricKit and logs each diagnostic payload's summary
/// through `LillistLog.metrics`, so day-after crash/hang/launch reports
/// land on the same unified-log subsystem the crash reporter collects.
///
/// MetricKit retains subscribers weakly, so `AppEnvironment` holds a
/// strong reference for the lifetime of the app. We log only
/// non-identifying summary fields (call-stack JSON is intentionally not
/// emitted — it can carry symbol names; the redactor is a backstop, not
/// a license to ship stacks).
final class MetricKitObserver: NSObject, MXMetricManagerSubscriber {
    /// Register with the shared manager. Idempotent per instance.
    func startReceiving() {
        MXMetricManager.shared.add(self)
    }

    /// Unregister. Called from `deinit` defensively.
    func stopReceiving() {
        MXMetricManager.shared.remove(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        LillistLog.metrics.notice(
            "MetricKit metric payloads=\(payloads.count, privacy: .public)"
        )
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let launches = payload.appLaunchDiagnostics?.count ?? 0
            let cpuExceptions = payload.cpuExceptionDiagnostics?.count ?? 0
            let diskWrites = payload.diskWriteExceptionDiagnostics?.count ?? 0
            LillistLog.metrics.notice(
                "MetricKit diagnostics crashes=\(crashes, privacy: .public) hangs=\(hangs, privacy: .public) launches=\(launches, privacy: .public) cpu=\(cpuExceptions, privacy: .public) disk=\(diskWrites, privacy: .public)"
            )
        }
    }
}
