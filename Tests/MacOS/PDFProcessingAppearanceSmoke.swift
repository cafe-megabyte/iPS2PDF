import AppKit
import PDFKit
import Foundation

// An independent renderer check for native-engine output. This does not use
// PDFium and deliberately opens each written PDF again through Apple's PDFKit.
@main
struct PDFProcessingAppearanceSmoke {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else {
            fatalError("Usage: PDFProcessingAppearanceSmoke OUTPUT_DIRECTORY INPUT_PDF...")
        }
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for path in arguments.dropFirst(2) {
            let input = URL(fileURLWithPath: path)
            guard let pdf = PDFDocument(url: input), let page = pdf.page(at: 0) else {
                fatalError("PDFKit could not reopen a synthetic test PDF")
            }
            let bounds = page.bounds(for: .mediaBox)
            let thumbnail = page.thumbnail(of: NSSize(width: bounds.width * 2, height: bounds.height * 2), for: .mediaBox)
            guard let tiff = thumbnail.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("PDFKit could not render a synthetic test PDF")
            }
            let filename = input.deletingPathExtension().lastPathComponent + "-apple.png"
            try png.write(to: output.appendingPathComponent(filename))
            let fields = page.annotations.filter { $0.type?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "Widget" }.map {
                ($0.fieldName ?? "") + "=" + ($0.widgetStringValue ?? "")
            }.sorted()
            print("PDFKit \(input.lastPathComponent): \(pdf.pageCount) pages; widgets \(fields)")
        }
    }
}
