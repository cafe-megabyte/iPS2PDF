import Foundation

struct PDFInspectionReport: Equatable, Sendable {
    let fileName: String
    var sections: [PDFInfoSection] = []
    var notices: [String] = []
    var pagesRead = 0
    var pageCount = 0
    var isComplete = false
    var isLocked = false
    var allowsResourceExporting = false
    var declaredStandards: [String] = []

    var hasConformityDeclaration: Bool { !declaredStandards.isEmpty }

    var exportableResources: [PDFExtractableResource] {
        var seen: Set<String> = []
        return sections.compactMap(\.resource).filter { seen.insert($0.id).inserted }
    }

    var fontWarnings: [PDFInfoSection] {
        sections.filter { $0.category == .fonts && $0.warning != nil }
    }

    var warningSummary: String? {
        guard !fontWarnings.isEmpty else { return nil }
        if fontWarnings.count == 1 { return String(localized: "1 font not embedded") }
        return String.localizedStringWithFormat(
            String(localized: "%lld fonts not embedded"), Int64(fontWarnings.count)
        )
    }

    func sections(in category: PDFInfoCategory) -> [PDFInfoSection] {
        var matching = sections.filter { $0.category == category }
        if category == .overview, !notices.isEmpty {
            matching.insert(PDFInfoSection(id: "analysis-notices", category: .overview, title: String(localized: "Analysis details"), fields: notices.enumerated().map { PDFInfoField(String(localized: "Notice") + " \($0.offset + 1)", $0.element, id: "notice-\($0.offset)") }, initiallyExpanded: false), at: 0)
        }
        guard category == .fonts else { return matching }
        return matching.sorted {
            if ($0.warning != nil) != ($1.warning != nil) { return $0.warning != nil }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var plainText: String { paragraphs.map(\.text).joined(separator: "\n\n") + "\n" }
}
