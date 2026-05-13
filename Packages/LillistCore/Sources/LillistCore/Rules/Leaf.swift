import Foundation

/// A single field/operator/value triple. Codable synthesis is automatic.
public struct Leaf: Codable, Sendable, Equatable {
    public var field: Field
    public var op: Op
    public var value: Value

    public init(field: Field, op: Op, value: Value) {
        self.field = field
        self.op = op
        self.value = value
    }
}
