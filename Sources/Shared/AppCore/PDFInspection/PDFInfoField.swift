import Foundation

enum PDFInfoFieldEmphasis: Equatable, Sendable {
    case standardDeclaration
    case warning
}

struct PDFInfoField: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
    let emphasis: PDFInfoFieldEmphasis?

    init(
        _ label: String,
        _ value: String,
        id: String? = nil,
        emphasis: PDFInfoFieldEmphasis? = nil
    ) {
        self.id = id ?? label
        self.label = String(localized: String.LocalizationValue(label))
        self.value = value
        self.emphasis = emphasis
    }
}
