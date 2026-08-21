import Foundation

final class GhostscriptConverter: FileConverting, @unchecked Sendable {
    private let helper = EnhancedSecurityClient()

    func validateJoboptions(at joboptionsURL: URL) async throws {
        // The host performs only non-executing lexical/structural validation.
        _ = try LosslessJoboptionsDocument(data: Data(contentsOf: joboptionsURL))
        // PostScript acceptance is deliberately confined to Enhanced Security.
        do {
            try await helper.validate(joboptionsURL: joboptionsURL)
        } catch let failure as ConversionFailure {
            var parts = [failure.localizedMessage]
            if let diagnostics = failure.diagnostics { parts.append(diagnostics) }
            if let returnCode = failure.returnCode {
                parts.append(String(format: String(localized: "error_return_code_format"), returnCode))
            }
            throw ConversionFailure.joboptions(diagnostics: parts.joined(separator: "\n\n"))
        }
    }

    func convert(
        sourceURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        standard: PDFStandard,
        securityLimitsEnabled: Bool
    ) async throws {
        try await helper.convert(
            inputURL: sourceURL,
            outputURL: outputURL,
            joboptionsURL: joboptionsURL,
            standard: standard,
            limitsEnabled: securityLimitsEnabled
        )
    }
}
