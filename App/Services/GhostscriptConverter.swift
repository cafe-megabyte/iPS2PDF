import Foundation

final class GhostscriptConverter: FileConverting, @unchecked Sendable {
    func convert(sourceURL: URL, outputURL: URL, pdfVersion: PDFVersion) async throws {
        let inputPath = sourceURL.path
        let outputPath = outputURL.path
        let version = pdfVersion.rawValue

        try await Task.detached(priority: .userInitiated) {
            var diagnostics = Array<CChar>(repeating: 0, count: 320)
            var returnCode: Int32 = 0
            var stage: Int32 = 0

            let bridgeStatus = inputPath.withCString { inputPointer in
                outputPath.withCString { outputPointer in
                    version.withCString { versionPointer in
                        gs_convert_to_pdf(
                            inputPointer,
                            outputPointer,
                            versionPointer,
                            &diagnostics,
                            diagnostics.count,
                            &returnCode,
                            &stage
                        )
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
}
