import Foundation

enum JoboptionsValue: Equatable, Sendable {
    case boolean(Bool)
    case number(Double, original: String)
    case name(String)
    case string(String)
    case array([JoboptionsValue])
    case dictionary([String: JoboptionsValue])
    case raw(String)

    var boolValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value, _) = self else { return nil }
        return value
    }

    var textualValue: String? {
        switch self {
        case let .name(value), let .string(value), let .raw(value): value
        case let .number(_, original): original
        case let .boolean(value): value ? "true" : "false"
        case .array, .dictionary: nil
        }
    }

    var postScript: String {
        switch self {
        case let .boolean(value):
            return value ? "true" : "false"
        case let .number(_, original):
            return original
        case let .name(value):
            return "/\(value)"
        case let .string(value):
            return PostScriptStringCodec.encodeLiteral(value)
        case let .array(values):
            return "[\(values.map(\.postScript).joined(separator: " "))]"
        case let .dictionary(values):
            let body = values.sorted { $0.key < $1.key }
                .map { "/\($0.key) \($0.value.postScript)" }
                .joined(separator: " ")
            return "<< \(body) >>"
        case let .raw(value):
            return value
        }
    }

}
