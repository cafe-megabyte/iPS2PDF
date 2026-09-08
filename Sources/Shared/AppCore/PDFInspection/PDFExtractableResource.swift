import Foundation

struct PDFExtractableResource: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let fingerprint: String
    let kind: PDFExtractableResourceKind
    let format: PDFExtractableResourceFormat
    let suggestedFilename: String
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    var bitsPerComponent: Int? = nil
    var isFontSubset = false

    init(fingerprint: String, kind: PDFExtractableResourceKind,
         format: PDFExtractableResourceFormat, suggestedFilename: String,
         identityQualifier: String = "", pixelWidth: Int? = nil,
         pixelHeight: Int? = nil, bitsPerComponent: Int? = nil,
         isFontSubset: Bool = false) {
        self.fingerprint = fingerprint
        self.kind = kind
        self.format = format
        self.suggestedFilename = suggestedFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bitsPerComponent = bitsPerComponent
        self.isFontSubset = isFontSubset
        id = [kind.rawValue, fingerprint, identityQualifier].filter { !$0.isEmpty }.joined(separator: ":")
    }
}
