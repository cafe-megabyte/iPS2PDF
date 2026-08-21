import Foundation

struct GhostscriptCompatibilityIssue: Identifiable, Equatable, Sendable {
    let key: String
    let currentValue: String
    let adjustedValue: String
    let reason: String

    var id: String { key }

    var summary: String {
        "\(localizedKey): \(localizedValue(currentValue)) → \(localizedValue(adjustedValue))"
    }

    private var localizedKey: String {
        DistillerOptionCatalog.byKey[key]?.localizedTitle ?? "/\(key)"
    }

    private func localizedValue(_ value: String) -> String {
        switch value {
        case "true": DistillerOptionCatalog.localizedChoice("True")
        case "false": DistillerOptionCatalog.localizedChoice("False")
        default: DistillerOptionCatalog.localizedChoice(value)
        }
    }
}
