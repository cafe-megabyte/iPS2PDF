import Foundation

struct PDFInfoSection: Identifiable, Equatable, Sendable {
    let id: String
    let category: PDFInfoCategory
    var title: String
    var fields: [PDFInfoField]
    var warning: String? = nil
    var initiallyExpanded = true
    var isComplete = true
}
