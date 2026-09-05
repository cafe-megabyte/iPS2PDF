import AppKit
import UniformTypeIdentifiers

@MainActor
enum MacOSPDFReportSharing {
    static let warningColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.46, green: 0.29, blue: 0.07, alpha: 0.72)
            : NSColor(calibratedRed: 1, green: 0.86, blue: 0.48, alpha: 0.58)
    }
    static func rtf(_ report: PDFInspectionReport) throws -> Data {
        let text = NSMutableAttributedString(string: "")
        let paragraphs = report.paragraphs
        for (index, paragraph) in paragraphs.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
            switch paragraph.style {
            case .title: attributes[.font] = NSFont.boldSystemFont(ofSize: 22)
            case .heading: attributes[.font] = NSFont.boldSystemFont(ofSize: 17)
            case .subheading: attributes[.font] = NSFont.boldSystemFont(ofSize: 13)
            case .warning: attributes[.backgroundColor] = NSColor(calibratedRed: 1, green: 0.86, blue: 0.48, alpha: 0.58)
            case .metadata: attributes[.font] = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            case .body: break
            }
            text.append(NSAttributedString(string: paragraph.text + (index == paragraphs.count - 1 ? "\n" : "\n\n"), attributes: attributes))
        }
        return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    static func copy(_ report: PDFInspectionReport) throws {
        let data = try rtf(report)
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString(report.plainText, forType: .string)
        item.setData(data, forType: .rtf)
        NSPasteboard.general.writeObjects([item])
    }
    static func export(_ report: PDFInspectionReport, formatted: Bool, window: NSWindow) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [formatted ? .rtf : .utf8PlainText]
        panel.nameFieldStringValue = URL(fileURLWithPath: report.fileName).deletingPathExtension().lastPathComponent + "-Info." + (formatted ? "rtf" : "txt")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do { try (formatted ? rtf(report) : Data(report.plainText.utf8)).write(to: url, options: .atomic) }
            catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
}
