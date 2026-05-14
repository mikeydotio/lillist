import Foundation
import CoreData
@preconcurrency import UserNotifications

/// Reconciles `NotificationSpec` rows against the system notification center.
///
/// Single entry point: `reconcile(taskID:)`. Every mutation that affects
/// scheduling (`TaskStore.update`, `.transition`, soft-delete, restore,
/// `NotificationSpecStore.add/update/delete`, recurrence spawn, snooze
/// handler) calls this method after its own save.
///
/// Identifier format (design Section 4 cross-device de-dup):
/// `"\(specID)#\(deviceFingerprint)"`.
public actor NotificationScheduler {
    private let persistence: PersistenceController
    private let specStore: NotificationSpecStore
    private let center: any UNUserNotificationCenterProtocol
    private let snoozeRegistry: SnoozeRegistry
    private let deviceFingerprint: String
    private(set) public var defaultAllDayHour: Int
    private(set) public var defaultAllDayMinute: Int
    private let timeZone: TimeZone

    public init(
        persistence: PersistenceController,
        specs: NotificationSpecStore,
        center: any UNUserNotificationCenterProtocol,
        snoozeRegistry: SnoozeRegistry,
        deviceFingerprint: String,
        defaultAllDayHour: Int,
        defaultAllDayMinute: Int,
        timeZone: TimeZone
    ) {
        self.persistence = persistence
        self.specStore = specs
        self.center = center
        self.snoozeRegistry = snoozeRegistry
        self.deviceFingerprint = deviceFingerprint
        self.defaultAllDayHour = defaultAllDayHour
        self.defaultAllDayMinute = defaultAllDayMinute
        self.timeZone = timeZone
    }

    // MARK: - Public reconciliation entry point

    public func reconcile(taskID: UUID) async {
        do {
            let snapshot = try await loadTaskSnapshot(taskID: taskID)
            // Ensure default specs exist (or don't) per the task's anchor fields.
            try await materializeDefaultSpecs(for: snapshot)

            let specs = try await specStore.specs(forTask: taskID)
            let desired = computeDesiredRequests(task: snapshot, specs: specs)

            let pending = await center.pendingNotificationRequests()
            // Match by task identity via userInfo + device fingerprint suffix.
            // Filtering by current spec IDs alone misses pending requests
            // whose specs were just deleted (e.g. by materializeDefaultSpecs
            // when an anchor field is cleared).
            let ourPending = pending.filter { isPendingForTask($0, taskID: taskID) }
            let pendingByID = Dictionary(uniqueKeysWithValues: ourPending.map { ($0.identifier, $0) })
            let desiredByID = Dictionary(uniqueKeysWithValues: desired.map { ($0.identifier, $0) })

            // Remove stale.
            let toRemove = ourPending.map(\.identifier).filter { desiredByID[$0] == nil }
            if toRemove.isEmpty == false {
                await center.removePendingNotificationRequests(withIdentifiers: toRemove)
            }
            // Add missing.
            for req in desired where pendingByID[req.identifier] == nil {
                try await center.add(req)
            }
        } catch {
            // Reconciliation must not throw outward — log via OSLog from
            // the app layer if needed. Failures here mean a transient
            // store/center error; next reconcile will retry.
        }
    }

    // MARK: - Snapshot

    struct TaskSnapshot: Sendable {
        let id: UUID
        let title: String
        let status: Status
        let start: Date?
        let startHasTime: Bool
        let deadline: Date?
        let deadlineHasTime: Bool
        let deletedAt: Date?
    }

    private func loadTaskSnapshot(taskID: UUID) async throws -> TaskSnapshot {
        let ctx = persistence.container.viewContext
        return try await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            req.fetchLimit = 1
            guard let m = try ctx.fetch(req).first else { throw LillistError.notFound }
            return TaskSnapshot(
                id: m.id ?? UUID(),
                title: m.title ?? "",
                status: m.status,
                start: m.start,
                startHasTime: m.startHasTime,
                deadline: m.deadline,
                deadlineHasTime: m.deadlineHasTime,
                deletedAt: m.deletedAt
            )
        }
    }

    // MARK: - Default spec materialization (Layer 1/2)

    private func materializeDefaultSpecs(for task: TaskSnapshot) async throws {
        let existing = try await specStore.specs(forTask: task.id)
        let existingDefaultStart = existing.first { $0.kind == .defaultStart }
        let existingDefaultDeadline = existing.first { $0.kind == .defaultDeadline }

        // Default start: present iff task.start != nil and not soft-deleted and not closed.
        let needsStart = task.start != nil && task.deletedAt == nil && task.status != .closed
        if needsStart && existingDefaultStart == nil {
            _ = try await specStore.add(taskID: task.id, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        } else if needsStart == false, let s = existingDefaultStart {
            try await specStore.delete(id: s.id)
        }

        let needsDeadline = task.deadline != nil && task.deletedAt == nil && task.status != .closed
        if needsDeadline && existingDefaultDeadline == nil {
            _ = try await specStore.add(taskID: task.id, kind: .defaultDeadline, offsetMinutes: nil, fireDate: nil)
        } else if needsDeadline == false, let s = existingDefaultDeadline {
            try await specStore.delete(id: s.id)
        }
    }

    // MARK: - Desired request computation

    func computeDesiredRequests(
        task: TaskSnapshot,
        specs: [NotificationSpecStore.SpecRecord]
    ) -> [UNNotificationRequest] {
        // Closed or soft-deleted tasks: no pending requests at all
        // (design Section 4: "→ Closed: cancel all pending").
        guard task.status != .closed, task.deletedAt == nil else { return [] }

        var out: [UNNotificationRequest] = []
        for spec in specs {
            guard let fireDate = computeFireDate(for: spec, task: task) else { continue }
            // Skip past-due fire dates.
            guard fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = task.title
            content.categoryIdentifier = NotificationCategoryID.categoryID(for: spec.kind)
            content.userInfo = [
                "taskID": task.id.uuidString,
                "specID": spec.id.uuidString,
                "kind": spec.kind.rawValue
            ]

            let trigger = makeCalendarTrigger(for: fireDate)
            let identifier = identifier(for: spec.id)
            out.append(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
        return out
    }

    func computeFireDate(
        for spec: NotificationSpecStore.SpecRecord,
        task: TaskSnapshot
    ) -> Date? {
        // Snooze: if `snoozedUntil` is in the future, that wins.
        if let snoozed = spec.snoozedUntil, snoozed > Date() {
            return snoozed
        }

        switch spec.kind {
        case .defaultStart:
            return resolvedAnchorDate(date: task.start, hasTime: task.startHasTime)
        case .defaultDeadline:
            return resolvedAnchorDate(date: task.deadline, hasTime: task.deadlineHasTime)
        case .offsetStart:
            guard let anchor = resolvedAnchorDate(date: task.start, hasTime: task.startHasTime),
                  let offset = spec.offsetMinutes else { return nil }
            return anchor.addingTimeInterval(TimeInterval(offset) * 60)
        case .offsetDeadline:
            guard let anchor = resolvedAnchorDate(date: task.deadline, hasTime: task.deadlineHasTime),
                  let offset = spec.offsetMinutes else { return nil }
            return anchor.addingTimeInterval(TimeInterval(offset) * 60)
        case .nudge:
            return spec.fireDate
        }
    }

    /// Resolves an anchor date: time-bearing returns the raw date; all-day
    /// returns the date with the default all-day hour:minute applied in the
    /// configured time zone (design Section 4 Layer 2).
    func resolvedAnchorDate(date: Date?, hasTime: Bool) -> Date? {
        guard let date else { return nil }
        if hasTime { return date }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var components = cal.dateComponents([.year, .month, .day], from: date)
        components.hour = defaultAllDayHour
        components.minute = defaultAllDayMinute
        components.second = 0
        return cal.date(from: components) ?? date
    }

    /// `UNCalendarNotificationTrigger` is DST-safe: it stores the components,
    /// not an absolute interval (design Section 8 — "DST: wall-clock time
    /// preserved across transitions via DateComponents-based triggers").
    func makeCalendarTrigger(for fireDate: Date) -> UNCalendarNotificationTrigger {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        var components = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        components.timeZone = timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    // MARK: - Identifier helpers

    func identifier(for specID: UUID) -> String {
        "\(specID.uuidString)#\(deviceFingerprint)"
    }

    /// True if the pending request belongs to this device AND to the task
    /// being reconciled. Matching by `userInfo["taskID"]` (rather than by
    /// looking up specs) makes reconciliation correct even when a spec
    /// was just deleted in this reconcile cycle.
    private func isPendingForTask(_ request: UNNotificationRequest, taskID: UUID) -> Bool {
        guard request.identifier.hasSuffix("#\(deviceFingerprint)") else { return false }
        guard let taskIDString = request.content.userInfo["taskID"] as? String else { return false }
        return taskIDString == taskID.uuidString
    }

    // MARK: - Public Layer 3 API

    /// Add a per-task offset reminder relative to either `start` or `deadline`.
    /// Negative `offsetMinutes` fires before the anchor; positive after.
    @discardableResult
    public func addOffset(
        taskID: UUID,
        anchor: NotificationKind.Anchor,
        offsetMinutes: Int32
    ) async throws -> UUID {
        let kind: NotificationKind
        switch anchor {
        case .start: kind = .offsetStart
        case .deadline: kind = .offsetDeadline
        }
        let id = try await specStore.add(
            taskID: taskID,
            kind: kind,
            offsetMinutes: offsetMinutes,
            fireDate: nil
        )
        await reconcile(taskID: taskID)
        return id
    }

    // MARK: - Public Layer 4 API

    /// Install or replace the daily morning summary at the given time.
    /// The body is supplied at delivery via a notification content extension
    /// that queries `LillistCore` for today's tasks (design Section 4 Layer 4).
    public func installMorningSummary(hour: Int, minute: Int) async {
        await center.removePendingNotificationRequests(withIdentifiers: [MorningSummary.requestID])

        let content = UNMutableNotificationContent()
        content.title = "Today in Lillist"
        content.body = ""  // Filled by content extension at delivery time.
        content.categoryIdentifier = MorningSummary.categoryID

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: MorningSummary.requestID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func uninstallMorningSummary() async {
        await center.removePendingNotificationRequests(withIdentifiers: [MorningSummary.requestID])
    }
}
