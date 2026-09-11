import Foundation

protocol FileConverting: Sendable {
    func validateJoboptions(at joboptionsURL: URL) async throws

    func convert(
        sourceURL: URL,
        outputURL: URL,
        joboptionsURL: URL,
        standard: PDFStandard,
        securityLimitsEnabled: Bool,
        postScriptRandomSeed: Int,
        inputPassword: String?
    ) async throws

    func convertToPostScript(
        sourceURL: URL,
        outputURL: URL,
        securityLimitsEnabled: Bool,
        postScriptRandomSeed: Int,
        inputPassword: String?
    ) async throws
}
