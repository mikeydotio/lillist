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
public actor NotificationScheduler: NotificationReconciling {
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

            // Stale = pending whose identifier is no longer desired.
            // Changed = pending whose identifier is still desired but whose
            // trigger components differ (e.g. all-day default-time preference
            // change — same spec, new wall-clock target).
            //
            // Built with for-loops rather than compactMap so the actor-isolated
            // `desiredByID` dictionary is not captured into a closure (Swift 6
            // strict-concurrency `SendingRisksDataRace`).
            var toRemove: [String] = []
            for p in ourPending {
                if let d = desiredByID[p.identifier] {
                    if triggersDiffer(p.trigger, d.trigger) {
                        toRemove.append(p.identifier)
                    }
                } else {
                    toRemove.append(p.identifier)
                }
            }
            if toRemove.isEmpty == false {
                await center.removePendingNotificationRequests(withIdentifiers: toRemove)
            }

            // Add missing — and re-add the ones we just removed because of a
            // trigger change.
            let removedSet = Set(toRemove)
            for req in desired where pendingByID[req.identifier] == nil || removedSet.contains(req.identifier) {
                try await center.add(req)
            }
        } catch {
            // Reconciliation must not throw outward — log via OSLog from
            // the app layer if needed. Failures here mean a transient
            // store/center error; next reconcile will retry.
        }
    }

    /// True if two `UNCalendarNotificationTrigger`s would fire at different
    /// wall-clock instants. Used by `reconcile` to detect that a still-known
    /// spec's scheduled trigger has changed (e.g. preference-driven time
    /// shift, snooze, etc.) and needs replacing.
    private func triggersDiffer(_ a: UNNotificationTrigger?, _ b: UNNotificationTrigger?) -> Bool {
        guard let a = a as? UNCalendarNotificationTrigger,
              let b = b as? UNCalendarNotificationTrigger else { return false }
        let ac = a.dateComponents
        let bc = b.dateComponents
        return ac.year != bc.year
            || ac.month != bc.month
            || ac.day != bc.day
            || ac.hour != bc.hour
            || ac.minute != bc.minute
            || ac.second != bc.second
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

        // Default specs exist iff their anchor field is present. Closed
        // and soft-deleted status is handled separately in
        // `computeDesiredRequests` so that spec rows are *preserved*
        // across status transitions — design Section 4: "→ Closed:
        // cancel all pending (spec rows preserved for history)". On
        // re-open, the still-present spec is re-registered.
        let needsStart = task.start != nil
        if needsStart && existingDefaultStart == nil {
            _ = try await specStore.add(taskID: task.id, kind: .defaultStart, offsetMinutes: nil, fireDate: nil)
        } else if needsStart == false, let s = existingDefaultStart {
            try await specStore.delete(id: s.id)
        }

        let needsDeadline = task.deadline != nil
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
            // Cross-device de-dup: skip when `lastFiredAt` is at or after
            // the currently-computed fire time (within a small wall-clock
            // tolerance). The lastFiredAt is written by `recordFired`
            // when a notification is delivered on some device; other
            // devices then drop their matching pending. Crucially this
            // check is fireDate-relative, not absolute — if the user
            // edits the deadline forward after a fire, the new fireDate
            // is greater than lastFiredAt and the spec re-fires for the
            // new date (design Section 4).
            if let lastFired = spec.lastFiredAt,
               lastFired >= fireDate.addingTimeInterval(-60) {
                continue
            }
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

    // MARK: - Bootstrap

    /// Call once on app launch. Publishes the notification categories
    /// (one per `NotificationKind`, plus the morning summary category)
    /// so that the system can dispatch action taps to the app.
    public func bootstrap() async {
        let categories = await NotificationCategoryFactory.makeCategories(registry: snoozeRegistry)
        await center.setNotificationCategories(categories)
    }

    // MARK: - Preference change

    /// Update the default all-day notification time. Reconciles every task
    /// that has at least one all-day default spec (design Section 4 Layer 2:
    /// the configured time is used at delivery, so changing it must
    /// re-trigger every dependent request).
    public func updateDefaultAllDayTime(hour: Int, minute: Int) async {
        self.defaultAllDayHour = hour
        self.defaultAllDayMinute = minute
        let affected = await tasksWithAllDayDefaults()
        for taskID in affected {
            await reconcile(taskID: taskID)
        }
    }

    private func tasksWithAllDayDefaults() async -> [UUID] {
        let ctx = persistence.container.viewContext
        return await ctx.perform {
            let req = NSFetchRequest<LillistTask>(entityName: "LillistTask")
            req.predicate = NSPredicate(
                format: "(start != nil AND startHasTime == NO) OR (deadline != nil AND deadlineHasTime == NO)"
            )
            let tasks = (try? ctx.fetch(req)) ?? []
            return tasks.compactMap(\.id)
        }
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

    // MARK: - Public Nudge API

    /// Schedule a first-class nudge with an absolute `fireDate`. The nudge
    /// is independent of `start`/`deadline` and survives changes to them
    /// (design Section 4: "Nudges. First-class NotificationSpec of kind
    /// nudge with an absolute fireDate. Independent of start/deadline").
    @discardableResult
    public func addNudge(taskID: UUID, fireDate: Date) async throws -> UUID {
        let id = try await specStore.add(
            taskID: taskID,
            kind: .nudge,
            offsetMinutes: nil,
            fireDate: fireDate
        )
        await reconcile(taskID: taskID)
        return id
    }

    // MARK: - Snooze handling

    /// Apply a snooze action to a spec. Writes `snoozedUntil` and reconciles.
    /// Call from your `UNUserNotificationCenterDelegate` `didReceive` handler.
    public func handleSnoozeAction(
        actionID: String,
        specID: UUID,
        deliveredAt: Date
    ) async throws {
        guard let action = await snoozeRegistry.action(id: actionID) else {
            throw LillistError.validationFailed([
                .init(field: "actionID", message: "unknown snooze action: \(actionID)")
            ])
        }
        let spec = try await specStore.fetch(id: specID)
        let until = action.compute(spec, deliveredAt)
        try await specStore.update(id: specID) { d in
            d.snoozedUntil = until
        }
        await reconcile(taskID: spec.taskID)
    }

    // MARK: - Fired-handler

    /// Record that a notification fired on this device. Call from your
    /// `UNUserNotificationCenterDelegate` `willPresent` handler. Other
    /// devices observe the change via CloudKit and remove their matching
    /// pending request (design Section 4 cross-device de-dup).
    public func recordFired(specID: UUID, at date: Date = Date()) async {
        try? await specStore.recordLastFired(id: specID, at: date)
        if let spec = try? await specStore.fetch(id: specID) {
            await reconcile(taskID: spec.taskID)
        }
    }
}
