import Foundation

struct PDFPageCompressionOverride: Codable, Equatable, Sendable {
    let pageIndex: Int
    let options: PDFCompressionOptions

    var isValid: Bool {
        (0...Int(Int32.max)).contains(pageIndex) && options.isValid
    }
}
