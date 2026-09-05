import Foundation

struct PDFReportParagraph: Sendable {
    enum Style: Sendable, Equatable { case title, heading, subheading, body, warning, metadata }
    let text: String
    let style: Style
}

extension PDFInspectionReport {
    var paragraphs: [PDFReportParagraph] {
        var result: [PDFReportParagraph] = []
        func append(_ text: String, _ style: PDFReportParagraph.Style = .body) {
            result.append(PDFReportParagraph(text: text, style: style))
        }
        append(String(localized: "PDF information"), .title)
        append(fileName)
        if !isComplete { append(String(localized: "Analysis incomplete")) }
        for notice in notices { append(notice) }
        if let warningSummary {
            append(String(localized: "Problems"), .heading)
            append(warningSummary, .warning)
            for font in fontWarnings { append("• \(font.title): \(font.warning ?? "")", .warning) }
        }
        func appendSection(_ section: PDFInfoSection) {
            append(section.title, .subheading)
            if let warning = section.warning { append("⚠ \(warning)", .warning) }
            for field in section.fields { append("\(field.label): \(field.value)", section.id == "xmp" ? .metadata : .body) }
        }
        for category in PDFInfoCategory.allCases {
            append(category.title, .heading)
            let values = sections(in: category).filter { $0.id != "xmp" && $0.id != "analysis-notices" }
            if values.isEmpty { append(isComplete ? String(localized: "No entries found") : PDFInspectionFormat.unknown) }
            for section in values { appendSection(section) }
        }
        for section in sections where section.id == "xmp" { appendSection(section) }
        return result
    }
}
