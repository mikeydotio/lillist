/// The four reorder operations a task row can expose to VoiceOver.
///
/// Order matches `allCases` so callers iterate actions in their visual
/// (up → down → indent → outdent) order.
enum ReorderAction: CaseIterable, Equatable {
    case moveUp
    case moveDown
    case indent
    case outdent

    /// Stable source key used as the `accessibilityAction(named:)` string
    /// and as the catalog key. Localized at the call site via `.module`.
    var accessibilityKey: String {
        switch self {
        case .moveUp:   return "Move up"
        case .moveDown: return "Move down"
        case .indent:   return "Indent"
        case .outdent:  return "Outdent"
        }
    }
}

/// Pure router mapping each `ReorderAction` to its optional closure.
///
/// `availableActions` is exactly the set of actions whose closure is
/// non-nil, so a surface that doesn't wire (e.g.) indent/outdent never
/// advertises a phantom no-op action to assistive technology.
struct ReorderActionDispatch {
    private let onMoveUp: (() -> Void)?
    private let onMoveDown: (() -> Void)?
    private let onIndent: (() -> Void)?
    private let onOutdent: (() -> Void)?

    init(
        onMoveUp: (() -> Void)?,
        onMoveDown: (() -> Void)?,
        onIndent: (() -> Void)?,
        onOutdent: (() -> Void)?
    ) {
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onIndent = onIndent
        self.onOutdent = onOutdent
    }

    /// The actions that have a wired closure, in visual order.
    var availableActions: [ReorderAction] {
        ReorderAction.allCases.filter { closure(for: $0) != nil }
    }

    /// Invokes the closure for `action` if one is registered; otherwise
    /// does nothing.
    func invoke(_ action: ReorderAction) {
        closure(for: action)?()
    }

    private func closure(for action: ReorderAction) -> (() -> Void)? {
        switch action {
        case .moveUp:   return onMoveUp
        case .moveDown: return onMoveDown
        case .indent:   return onIndent
        case .outdent:  return onOutdent
        }
    }
}
