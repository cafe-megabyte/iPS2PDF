import Foundation
import UniformTypeIdentifiers

struct IncomingDocumentRouter {
    func classify(_ stagedURL: URL, purpose: IncomingDocumentPurpose = .automatic) throws -> IncomingDocument {
        let resourceValues = try stagedURL.resourceValues(
            forKeys: [.isRegularFileKey, .isReadableKey, .contentTypeKey]
        )
        guard resourceValues.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: stagedURL.path)
        else {
            throw ConversionFailure.inputCannotBeRead
        }

        if purpose == .automatic, try Self.isPDF(stagedURL) { return .pdfInformation(stagedURL) }

        let extensionMatches = stagedURL.pathExtension
            .caseInsensitiveCompare("joboptions") == .orderedSame
        let declaredTypeMatches = resourceValues.contentType?.conforms(to: .joboptions) == true
        guard extensionMatches || declaredTypeMatches else {
            return .conversionInput(stagedURL)
        }

        let data = try Data(contentsOf: stagedURL, options: [.mappedIfSafe])
        let document = try LosslessJoboptionsDocument(data: data)
        return .joboptions(stagedURL, document)
    }
    static func isPDF(_ url: URL) throws -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if url.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame { return true }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let header = try file.read(upToCount: 1024) ?? Data()
        // Recognize a PDF header within the first 1024 bytes, including files
        // received from providers with a missing or misleading extension.
        let bytes = Array(header)
        guard bytes.count >= 8 else { return false }
        for index in 0...(bytes.count - 8) {
            if bytes[index..<(index + 5)].elementsEqual([37, 80, 68, 70, 45]),
               (48...57).contains(bytes[index + 5]), bytes[index + 6] == 46,
               (48...57).contains(bytes[index + 7]) { return true }
        }
        return false
    }

}
