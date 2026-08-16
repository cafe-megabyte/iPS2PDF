import Foundation

final class GhostscriptConverter: FileConverting, @unchecked Sendable {
    func convert(
        sourceURL: URL,
        outputURL: URL,
        pdfVersion: PDFVersion,
        pdfaCompatibility: PDFACompatibility = .none
    ) async throws {
        let inputPath = sourceURL.path
        let outputPath = outputURL.path
        let version = pdfVersion.rawValue
        let pdfaVersion = pdfaCompatibility.ghostscriptPDFAValue
        let pdfaResourceDirectory: String?
        let pdfaDefinitionPath: String?

        if pdfaVersion != nil {
            guard let resourceDirectoryURL = Bundle.main.url(forResource: "Ghostscript", withExtension: nil),
                  let definitionURL = Bundle.main.url(
                    forResource: "PDFA_def",
                    withExtension: "ps",
                    subdirectory: "Ghostscript"
                  )
            else {
                throw ConversionFailure.ghostscriptConversion(
                    returnCode: 0,
                    diagnostics: "Missing bundled Ghostscript PDF/A resources."
                )
            }
            pdfaResourceDirectory = resourceDirectoryURL.path
            pdfaDefinitionPath = definitionURL.path
        } else {
            pdfaResourceDirectory = nil
            pdfaDefinitionPath = nil
        }

        try await Task.detached(priority: .userInitiated) {
            var diagnostics = Array<CChar>(repeating: 0, count: 320)
            var returnCode: Int32 = 0
            var stage: Int32 = 0

            let bridgeStatus = inputPath.withCString { inputPointer in
                outputPath.withCString { outputPointer in
                    version.withCString { versionPointer in
                        Self.withOptionalCString(pdfaVersion) { pdfaVersionPointer in
                            Self.withOptionalCString(pdfaDefinitionPath) { pdfaDefinitionPointer in
                                Self.withOptionalCString(pdfaResourceDirectory) { pdfaResourceDirectoryPointer in
                                    gs_convert_to_pdf(
                                        inputPointer,
                                        outputPointer,
                                        versionPointer,
                                        pdfaVersionPointer,
                                        pdfaDefinitionPointer,
                                        pdfaResourceDirectoryPointer,
                                        &diagnostics,
                                        diagnostics.count,
                                        &returnCode,
                                        &stage
                                    )
                                }
                            }
                        }
                    }
                }
            }

            guard bridgeStatus == 0 else {
                let capturedOutput = diagnostics.withUnsafeBufferPointer {
                    String(cString: $0.baseAddress!)
                }
                switch stage {
                case Int32(GS_BRIDGE_STAGE_NEW_INSTANCE.rawValue):
                    throw ConversionFailure.ghostscriptInstance(
                        returnCode: returnCode,
                        diagnostics: capturedOutput
                    )
                case Int32(GS_BRIDGE_STAGE_INITIALIZATION.rawValue):
                    throw ConversionFailure.ghostscriptInitialization(
                        returnCode: returnCode,
                        diagnostics: capturedOutput
                    )
                default:
                    throw ConversionFailure.ghostscriptConversion(
                        returnCode: returnCode,
                        diagnostics: capturedOutput
                    )
                }
            }
        }.value
    }

    private static func withOptionalCString<Result>(
        _ string: String?,
        _ body: (UnsafePointer<CChar>?) -> Result
    ) -> Result {
        guard let string else {
            return body(nil)
        }
        return string.withCString(body)
    }
}
