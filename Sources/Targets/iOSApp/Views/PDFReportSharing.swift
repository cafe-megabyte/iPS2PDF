import UIKit
import UniformTypeIdentifiers

@MainActor
enum PDFReportSharing {
    static func rtf(_ report: PDFInspectionReport) throws -> Data {
        let text = NSMutableAttributedString(string: "")
        let paragraphs = report.paragraphs
        for (index, paragraph) in paragraphs.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
            switch paragraph.style {
            case .title: attributes[.font] = UIFont.boldSystemFont(ofSize: 22)
            case .heading: attributes[.font] = UIFont.boldSystemFont(ofSize: 17)
            case .subheading: attributes[.font] = UIFont.boldSystemFont(ofSize: 13)
            case .warning: attributes[.backgroundColor] = UIColor.systemOrange.withAlphaComponent(0.20)
            case .metadata: attributes[.font] = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            case .body: break
            }
            text.append(NSAttributedString(string: paragraph.text + (index == paragraphs.count - 1 ? "\n" : "\n\n"), attributes: attributes))
        }
        return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    static func copy(_ report: PDFInspectionReport) throws {
        let data = try rtf(report)
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: report.plainText, UTType.rtf.identifier: data]])
    }
    static func export(_ report: PDFInspectionReport, formatted: Bool) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFReport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = URL(fileURLWithPath: report.fileName).deletingPathExtension().lastPathComponent
        let url = directory.appendingPathComponent(stem + "-Info." + (formatted ? "rtf" : "txt"))
        do {
            try (formatted ? rtf(report) : Data(report.plainText.utf8)).write(to: url, options: .atomic)
            return url
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }
}
