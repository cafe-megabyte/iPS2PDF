import Foundation

struct DistillerOptionDefinition: Identifiable, Sendable {
    let key: String
    let title: LocalizedStringResource
    let category: DistillerCategory
    let section: DistillerSection
    let kind: DistillerOptionKind
    let keyPaths: [JoboptionsKeyPath]
    let semanticEditor: DistillerSemanticEditor
    let classification: DistillerControlClassification
    let isDisabledBySelectedStandard: Bool
    let compatibilityNote: LocalizedStringResource?

    var id: String { key }

    var localizedTitle: String {
        String(localized: title)
    }

    var localizedHelp: String {
        keyPaths.map(\.description).joined(separator: ", ")
    }

    var localizedCompatibilityNote: String? {
        compatibilityNote.map { String(localized: $0) }
    }
}
