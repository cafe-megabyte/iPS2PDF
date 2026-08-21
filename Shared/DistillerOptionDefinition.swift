import Foundation

struct DistillerOptionDefinition: Identifiable, Sendable {
    let key: String
    let title: LocalizedStringResource
    let category: DistillerCategory
    let kind: DistillerOptionKind
    let help: String
    let compatibilityNote: LocalizedStringResource?

    var id: String { key }

    var localizedTitle: String {
        String(localized: title)
    }

    var localizedHelp: String {
        "/\(key)."
    }

    var localizedCompatibilityNote: String? {
        compatibilityNote.map { String(localized: $0) }
    }
}
