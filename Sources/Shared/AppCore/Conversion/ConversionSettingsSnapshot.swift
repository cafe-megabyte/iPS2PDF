import Foundation

struct ConversionSettingsSnapshot: Sendable {
    let effectiveJoboptionsData: Data
    let standard: PDFStandard
    let securityLimitsEnabled: Bool
    let postScriptRandomSeed: Int
}
