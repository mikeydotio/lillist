import Foundation
import os

/// Logging destination for the recurrence subsystem.
///
/// Recurrence input arriving from CloudKit decode, the Importer, or the CLI is
/// *untrusted*. When such input is out of range (e.g. a non-positive interval),
/// `RecurrenceRule` normalizes it rather than throwing — dropping the rule would
/// lose a user's recurrence on a single corrupt sync record. Each normalization
/// emits a `.warning` here so the event is visible in field diagnostics without
/// crashing or silently swallowing the corruption.
enum RecurrenceLog {
    /// Stable subsystem string, sibling to `CrashReporting.subsystemIdentifier`.
    static let subsystem = "io.mikey.lillist.recurrence"

    /// Logger for input-normalization events at the `CalendarRule` trust boundary.
    static let normalization = Logger(subsystem: subsystem, category: "normalization")
}
