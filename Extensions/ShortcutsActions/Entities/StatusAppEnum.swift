import AppIntents
import LillistCore

enum StatusAppEnum: String, AppEnum {
    case todo
    case started
    case blocked
    case closed

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Status"
    static let caseDisplayRepresentations: [StatusAppEnum: DisplayRepresentation] = [
        .todo: "To-do",
        .started: "Started",
        .blocked: "Blocked",
        .closed: "Closed"
    ]

    var coreStatus: Status {
        switch self {
        case .todo: return .todo
        case .started: return .started
        case .blocked: return .blocked
        case .closed: return .closed
        }
    }

    init(_ status: Status) {
        switch status {
        case .todo:    self = .todo
        case .started: self = .started
        case .blocked: self = .blocked
        case .closed:  self = .closed
        }
    }
}
