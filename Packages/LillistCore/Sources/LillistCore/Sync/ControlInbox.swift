import Foundation

/// Per-event, per-recipient control-message inbox over `KeyValueSyncStore`
/// (issue #71) — the propagation mechanism for "Reset Everywhere" and
/// "Reset & Re-seed from this device."
///
/// ## Why per-event keys, not a shared mailbox
///
/// Two designs were tried and rejected during planning before this one:
///
/// 1. **One array per recipient, appended to by every sender.** KVS has
///    no compare-and-swap and resolves same-key conflicts by
///    last-writer-wins on the whole value — a read-modify-write append
///    from two devices in the same window silently drops one of them.
/// 2. **One "latest event" slot per sender.** Fixes the multi-sender
///    race, but a *single* sender broadcasting twice in quick succession
///    (two unrelated events) overwrites its own first event before any
///    peer has read it — an unrelated signal is lost.
///
/// Both fail because they route a *stream* of events through a *mutable
/// value* at a shared key. This design instead gives every event its
/// own permanent key, `inbox.<recipientID>.<eventID>`, addressed to
/// exactly one recipient:
///
/// - **No write ever collides.** `eventID` is a fresh `UUID`, so no two
///   events — from the same or different senders — ever share a key.
///   Every key has exactly one writer, ever.
/// - **No read ever races a delete.** Because a key is addressed to one
///   recipient, only that recipient is ever looking at it — nobody else
///   can be surprised by it disappearing.
/// - **The live set self-cleans.** A recipient deletes its own key once
///   it has durably applied the event, so the collection doesn't grow
///   unboundedly in the common case (the residual: a device that never
///   comes back online leaves its entries orphaned — negligible against
///   KVS's 1 MB / 1024-key budget for a personal app's rare, deliberate
///   resets).
///
/// "Signal everyone" is implemented as N individual point-to-point
/// sends (one per known peer), not a broadcast primitive — KVS has no
/// multicast, and fan-out avoids the "who's allowed to delete a
/// broadcast message" ambiguity entirely.
public struct ControlInbox: Sendable {
    private static let keyPrefix = "inbox."

    private let kv: any KeyValueSyncStore

    public init(kv: any KeyValueSyncStore) {
        self.kv = kv
    }

    private static func key(recipient: String, eventID: UUID) -> String {
        "\(keyPrefix)\(recipient).\(eventID.uuidString)"
    }

    private static func recipientPrefix(_ recipient: String) -> String {
        "\(keyPrefix)\(recipient)."
    }

    /// Fan out `event` to every peer in `recipients`, one key each. All
    /// entries share `event.id` so they're correlatable as one logical
    /// broadcast even though they live at distinct keys.
    public func send(_ event: ResetControlEvent, to recipients: [RosterEntry]) {
        guard let data = try? Self.encode(event) else { return }
        for recipient in recipients {
            kv.set(data, forKey: Self.key(recipient: recipient.id, eventID: event.id))
        }
        if !recipients.isEmpty {
            kv.synchronize()
        }
    }

    /// Every not-yet-acknowledged event addressed to `recipientID`.
    public func pendingEvents(for recipientID: String) -> [ResetControlEvent] {
        kv.keys(withPrefix: Self.recipientPrefix(recipientID))
            .compactMap { key in kv.data(forKey: key).flatMap { try? Self.decode($0) } }
    }

    /// Delete the one key `recipient` owns for `eventID` — safe to call
    /// even if it's already gone (a crash-recovery retry, or a stale
    /// resend racing a completed apply both land here harmlessly).
    public func acknowledge(eventID: UUID, recipient: String) {
        kv.removeObject(forKey: Self.key(recipient: recipient, eventID: eventID))
        kv.synchronize()
    }

    private static func encode(_ event: ResetControlEvent) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(event)
    }

    private static func decode(_ data: Data) throws -> ResetControlEvent {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResetControlEvent.self, from: data)
    }
}
