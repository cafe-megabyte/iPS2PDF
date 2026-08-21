import Foundation
import UniformTypeIdentifiers

struct IncomingDocumentRouter {
    func classify(_ stagedURL: URL) throws -> IncomingDocument {
        let resourceValues = try stagedURL.resourceValues(
            forKeys: [.isRegularFileKey, .isReadableKey, .contentTypeKey]
        )
        guard resourceValues.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: stagedURL.path)
        else {
            throw ConversionFailure.inputCannotBeRead
        }

        let extensionMatches = stagedURL.pathExtension
            .caseInsensitiveCompare("joboptions") == .orderedSame
        let declaredTypeMatches = resourceValues.contentType?.conforms(to: .joboptions) == true
        let data = try Data(contentsOf: stagedURL, options: [.mappedIfSafe])

        do {
            let document = try LosslessJoboptionsDocument(data: data)
            return .joboptions(stagedURL, document)
        } catch {
            if extensionMatches || declaredTypeMatches {
                throw error
            }
            return .postScript(stagedURL)
        }
    }
}
