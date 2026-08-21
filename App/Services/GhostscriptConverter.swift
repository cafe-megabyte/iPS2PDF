import Foundation

final class GhostscriptConverter: FileConverting, @unchecked Sendable {
    private let helper = EnhancedSecurityClient()

    func validateJoboptions(at joboptionsURL: URL) async throws {
        // The host performs only non-executing lexical/structural validation.
        let document = try LosslessJoboptionsDocument(data: Data(contentsOf: joboptionsURL))
        let effectiveJoboptionsURL = try temporaryAdjustedJoboptionsURL(for: document)
        defer {
            if let effectiveJoboptionsURL {
                try? FileManager.default.removeItem(at: effectiveJoboptionsURL)
            }
        }
        // PostScript acceptance is deliberately confined to Enhanced Security.
        do {
            try await helper.validate(joboptionsURL: effectiveJoboptionsURL ?? joboptionsURL)
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
        let document = try LosslessJoboptionsDocument(data: Data(contentsOf: joboptionsURL))
        let effectiveJoboptionsURL = try temporaryAdjustedJoboptionsURL(for: document)
        defer {
            if let effectiveJoboptionsURL {
                try? FileManager.default.removeItem(at: effectiveJoboptionsURL)
            }
        }
        try await helper.convert(
            inputURL: sourceURL,
            outputURL: outputURL,
            joboptionsURL: effectiveJoboptionsURL ?? joboptionsURL,
            standard: standard,
            limitsEnabled: securityLimitsEnabled
        )
    }

    private func temporaryAdjustedJoboptionsURL(for document: LosslessJoboptionsDocument) throws -> URL? {
        let adjusted = try GhostscriptCompatibilityAdjuster.adjustedDocument(from: document)
        guard adjusted.data != document.data else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iPS2PDF-\(UUID().uuidString)")
            .appendingPathExtension("joboptions")
        try adjusted.data.write(to: url, options: [.atomic])
        return url
    }
}
