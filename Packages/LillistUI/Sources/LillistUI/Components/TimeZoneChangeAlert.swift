import SwiftUI

/// Offers to re-anchor reminders after the user travels to a new time zone —
/// `LIL-83`.
///
/// Pure presentation: the caller owns detection, the decision, and the writes.
/// Both answers are legitimate — a 9am medication reminder set in New York
/// arguably *should* stay 9am New York, and arguably *should* become 9am
/// wherever you now are — so this asks rather than deciding, and dismissing it
/// is a real answer (keep), never a deferral.
///
/// Presented as an alert rather than a sheet on purpose: it is a short, binary,
/// consequential question the user did not initiate, which is exactly the case
/// the platform alert convention exists for.
public struct TimeZoneChangeAlert: ViewModifier {
    /// What the user is being asked about.
    public struct Offer: Equatable, Sendable {
        /// Localized display name of the zone reminders are anchored to.
        public let fromName: String
        /// Localized display name of the zone the device is in now.
        public let toName: String
        /// How many reminders would move.
        public let count: Int

        public init(fromName: String, toName: String, count: Int) {
            self.fromName = fromName
            self.toName = toName
            self.count = count
        }
    }

    @Binding var offer: Offer?
    let onReschedule: (Offer) -> Void
    let onKeep: (Offer) -> Void

    public init(
        offer: Binding<Offer?>,
        onReschedule: @escaping (Offer) -> Void,
        onKeep: @escaping (Offer) -> Void
    ) {
        self._offer = offer
        self.onReschedule = onReschedule
        self.onKeep = onKeep
    }

    public func body(content: Content) -> some View {
        content.alert(
            "You've changed time zones",
            isPresented: Binding(
                get: { offer != nil },
                // Any dismissal that is not an explicit button tap must still
                // resolve the offer, or the prompt reappears on every
                // foreground. `onKeep` is the safe resolution: it changes no
                // reminder, it only stops asking about *this* move.
                set: { if $0 == false, let current = offer { onKeep(current); offer = nil } }
            ),
            presenting: offer
        ) { current in
            Button(Self.rescheduleTitle(current)) {
                onReschedule(current)
                offer = nil
            }
            Button("Keep Original Times", role: .cancel) {
                onKeep(current)
                offer = nil
            }
        } message: { current in
            Text(Self.message(current))
        }
    }

    /// - Note: `nonisolated static` so tests can exercise the copy without a
    ///   `MainActor` hop — the house pattern for pure helpers hung off a View.
    public nonisolated static func rescheduleTitle(_ offer: Offer) -> String {
        "Use \(offer.toName) Times"
    }

    public nonisolated static func message(_ offer: Offer) -> String {
        let noun = offer.count == 1 ? "reminder" : "reminders"
        return """
        Your \(offer.count) upcoming \(noun) \(offer.count == 1 ? "is" : "are") set \
        for \(offer.fromName). Keep them at their original times, or move them to \
        the same times in \(offer.toName)?
        """
    }
}

public extension View {
    /// Attach the `LIL-83` travel prompt. See ``TimeZoneChangeAlert``.
    func timeZoneChangeAlert(
        offer: Binding<TimeZoneChangeAlert.Offer?>,
        onReschedule: @escaping (TimeZoneChangeAlert.Offer) -> Void,
        onKeep: @escaping (TimeZoneChangeAlert.Offer) -> Void
    ) -> some View {
        modifier(TimeZoneChangeAlert(offer: offer, onReschedule: onReschedule, onKeep: onKeep))
    }
}
