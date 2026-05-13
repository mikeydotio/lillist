import Foundation

public enum AttachmentKind: Int, CaseIterable, Codable, Sendable {
    case image = 0
    case file = 1
    case linkPreview = 2
}
