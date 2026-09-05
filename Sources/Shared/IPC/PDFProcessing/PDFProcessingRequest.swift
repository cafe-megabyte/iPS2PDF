import Foundation

struct PDFProcessingRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case removeMetadata, compress }

    var version = PDFProcessingEnvelope.version
    let jobID: UUID
    let operation: Operation
    let preserveConformity: Bool
    let compression: PDFCompressionOptions
    var previewPage: Int? = nil

    var isValid: Bool {
        version == PDFProcessingEnvelope.version && compression.isValid &&
            (operation != .compress || !preserveConformity) &&
            (previewPage == nil || (operation == .compress && (0...Int(Int32.max)).contains(previewPage!)))
    }
}
