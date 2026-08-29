import Foundation

struct JoboptionsConsistencyIssue: Identifiable, Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        case standardPDFVersion
        case standardFontEmbedding
        case standardFontFailure
        case standardEncryption
        case standardPermissions
        case standardPDFXChecks
        case standardColorConversion
        case standardOutputProfile
        case standardTransparency
        case missingOutputProfile
        case transparency
        case flatePDF11

        var localizedDescription: String {
            switch self {
            case .standardPDFVersion:
                String(localized: "The selected PDF standard requires this PDF version.")
            case .standardFontEmbedding:
                String(localized: "The selected PDF standard requires all fonts to be embedded.")
            case .standardFontFailure:
                String(localized: "The selected PDF standard requires conversion to fail when a font cannot be embedded.")
            case .standardEncryption:
                String(localized: "PDF/A and PDF/X do not permit these encryption settings.")
            case .standardPermissions:
                String(localized: "PDF/A and PDF/X require unrestricted document permissions.")
            case .standardPDFXChecks:
                String(localized: "The PDF/X validation switches must match the selected standard.")
            case .standardColorConversion:
                String(localized: "The selected PDF standard requires this color conversion strategy.")
            case .standardOutputProfile:
                String(localized: "The selected PDF standard requires this output profile.")
            case .standardTransparency:
                String(localized: "The selected PDF standard does not permit transparency.")
            case .missingOutputProfile:
                String(localized: "A suitable installed output profile must be selected before conversion.")
            case .transparency:
                String(localized: "Transparency requires PDF 1.4 or newer.")
            case .flatePDF11:
                String(localized: "Flate image compression is not accepted by Ghostscript for PDF 1.1.")
            }
        }
    }

    let path: JoboptionsKeyPath
    let currentValue: JoboptionsValue?
    let proposedValue: JoboptionsValue?
    let reasonCode: Reason
    let ruleIdentifier: String
    let isAutomaticallyRepairable: Bool

    var id: String { "\(ruleIdentifier):\(path.description)" }
    var key: String { path.key ?? path.description }
    var reason: String { reasonCode.localizedDescription }

    var summary: String {
        let current = currentValue.map(Self.localizedValue) ?? String(localized: "Missing")
        let proposed = proposedValue.map(Self.localizedValue) ?? String(localized: "Manual selection required")
        return "\(path.description): \(current) → \(proposed)"
    }

    private static func localizedValue(_ value: JoboptionsValue) -> String {
        guard let text = value.textualValue else { return value.postScript }
        return switch text {
        case "true": DistillerOptionCatalog.localizedChoice("True")
        case "false": DistillerOptionCatalog.localizedChoice("False")
        default: DistillerOptionCatalog.localizedChoice(text)
        }
    }
}

typealias GhostscriptCompatibilityIssue = JoboptionsConsistencyIssue
