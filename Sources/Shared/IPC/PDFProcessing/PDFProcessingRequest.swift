import Foundation

struct PDFProcessingRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case removeMetadata, compress, addSignatures, extractResource }

    var version = PDFProcessingEnvelope.version
    let jobID: UUID
    let operation: Operation
    let preserveConformity: Bool
    let compression: PDFCompressionOptions
    var pageCompressionOverrides: [PDFPageCompressionOverride] = []
    var previewPage: Int? = nil
    var signaturePlacements: [PDFSignaturePlacement] = []
    var resourceFingerprint: String? = nil
    var resourceFormat: String? = nil
    var resourceWidth: Int? = nil
    var resourceHeight: Int? = nil
    var resourceBitsPerComponent: Int? = nil

    var isValid: Bool {
        guard version == PDFProcessingEnvelope.version, compression.isValid,
              operation != .compress || !preserveConformity,
              previewPageIsValid
        else { return false }
        guard pageCompressionOverrides.allSatisfy(\.isValid),
              pageCompressionOverrides.map(\.pageIndex) == pageCompressionOverrides.map(\.pageIndex).sorted(),
              Set(pageCompressionOverrides.map(\.pageIndex)).count == pageCompressionOverrides.count,
              operation == .compress || pageCompressionOverrides.isEmpty else { return false }
        if operation == .addSignatures {
            guard preserveConformity == false, previewPage == nil,
                  !signaturePlacements.isEmpty, signaturePlacements.count <= 10_000,
                  signaturePlacements.allSatisfy(\.isValid) else { return false }
        } else if !signaturePlacements.isEmpty { return false }
        if operation == .extractResource {
            let formats = ["embeddedFile", "jpeg", "jpeg2000", "png", "type1", "trueType",
                           "trueTypeCollection", "cff", "openType", "openTypeCollection", "icc", "xml"]
            guard preserveConformity == false, previewPage == nil,
                  let resourceFingerprint, resourceFingerprint.count == 64,
                  resourceFingerprint.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  let resourceFormat, formats.contains(resourceFormat)
            else { return false }
            for value in [resourceWidth, resourceHeight, resourceBitsPerComponent].compactMap({ $0 })
                where value <= 0 || value > Int(Int32.max) { return false }
        } else if resourceFingerprint != nil || resourceFormat != nil || resourceWidth != nil || resourceHeight != nil || resourceBitsPerComponent != nil {
            return false
        }
        return true
    }

    private var previewPageIsValid: Bool {
        guard let previewPage else { return true }
        return operation == .compress && (0...Int(Int32.max)).contains(previewPage)
    }
}
