import Foundation

enum DistillerOptionKind: Sendable {
    case boolean
    case integer(ClosedRange<Int>)
    case number(ClosedRange<Double>)
    case literal([String])
    case name([String])
    case string
}
