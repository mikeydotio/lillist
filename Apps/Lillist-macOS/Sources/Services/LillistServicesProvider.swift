import AppKit
import LillistCore

/// Plan 15 Task 23: AppKit Services provider. Exposes
/// "Add to Lillist as task" in the system Services submenu — selecting
/// text in any app and choosing this item creates a new task whose
/// title is the selected text.
///
/// Registered via `NSApp.servicesProvider = self` in
/// `AppDelegate.bootstrap()`. The corresponding `NSServices` entry in
/// `Info.plist` declares the service to the system so it appears in
/// the menu.
@MainActor
final class LillistServicesProvider: NSObject {
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    /// Matches the selector pattern AppKit calls when the user picks
    /// the service from the Services submenu. The selector name is
    /// declared in `Info.plist` under `NSServices > NSMessage`.
    ///
    /// - Parameters:
    ///   - pasteboard: contains the selection (any of the types
    ///     declared in `NSServices > NSSendTypes`).
    ///   - userData: unused; AppKit threads it through unchanged.
    ///   - error: writable autorelease pointer — populate with a
    ///     localized message if the service fails.
    @objc func addToLillistAsTask(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let raw = pasteboard.string(forType: .string),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Lillist could not read the selected text." as NSString
            return
        }
        // Title is the first line; everything else becomes notes.
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        let title = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        let notes = lines.dropFirst().joined(separator: "\n")

        Task { @MainActor in
            do {
                let id = try await environment.taskStore.create(title: title, placement: .top)
                if !notes.isEmpty {
                    try await environment.taskStore.update(id: id) { $0.notes = notes }
                }
            } catch {
                // The Services API has no inline UI to report failure;
                // log and move on. The user can confirm by opening
                // Lillist's main window. Log the error TYPE only as .public
                // (per the LillistLog privacy contract) — a full
                // localizedDescription can carry Core Data attribute values
                // or the store path, which the redactor only partly covers.
                LillistLog.app.error(
                    "Services create failed: \(String(describing: type(of: error)), privacy: .public)"
                )
            }
        }
    }
}
