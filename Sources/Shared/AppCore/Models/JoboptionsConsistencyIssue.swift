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
        case standardOutputProfileEmbedding
        case missingOutputProfileDisablesEmbedding
        case standardOutputConditionIdentifier
        case standardTrappedState
        case standardTransparency
        case transparency
        case flatePDF11
        case invalidPageRange
        case invalidDeviceResolution
        case invalidPageSize
        case invalidDownsampling
        case invalidCompression
        case invalidImageQuality
        case invalidImagePolicy
        case invalidMonoSmoothing
        case invalidPDFXBoxes

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
            case .standardOutputProfileEmbedding:
                String(localized: "PDF/X requires the selected output intent profile to be embedded.")
            case .missingOutputProfileDisablesEmbedding:
                String(localized: "An output intent profile cannot be embedded when no output profile is selected.")
            case .standardOutputConditionIdentifier:
                String(localized: "The PDF/X output condition identifier must match the selected output intent profile.")
            case .standardTrappedState:
                String(localized: "PDF/X requires the trapped state to be True or False.")
            case .standardTransparency:
                String(localized: "The selected PDF standard does not permit transparency.")
            case .transparency:
                String(localized: "Transparency requires PDF 1.4 or newer.")
            case .flatePDF11:
                String(localized: "Flate image compression is not accepted by Ghostscript for PDF 1.1.")
            case .invalidPageRange:
                String(localized: "The page range is incomplete or invalid.")
            case .invalidDeviceResolution:
                String(localized: "The device resolution must contain two positive values.")
            case .invalidPageSize:
                String(localized: "The page size must contain two positive values.")
            case .invalidDownsampling:
                String(localized: "Enabled downsampling requires a valid method, resolution, and threshold.")
            case .invalidCompression:
                String(localized: "Enabled image compression requires a supported filter.")
            case .invalidImageQuality:
                String(localized: "The selected image compression requires a valid quality value.")
            case .invalidImagePolicy:
                String(localized: "The image resolution policy contains an invalid value.")
            case .invalidMonoSmoothing:
                String(localized: "Monochrome smoothing requires a depth of 2, 4, or 8 bits.")
            case .invalidPDFXBoxes:
                String(localized: "The PDF/X page box settings are incomplete or invalid.")
            }
        }
    }

    let path: JoboptionsKeyPath
    let currentValue: JoboptionsValue?
    let proposedValue: JoboptionsValue
    let reasonCode: Reason
    let ruleIdentifier: String

    var id: String { "\(ruleIdentifier):\(path.description)" }
    var key: String { path.key ?? path.description }
    var reason: String { reasonCode.localizedDescription }

    var summary: String {
        let current = currentValue.map(Self.localizedValue) ?? String(localized: "Missing")
        let proposed = Self.localizedValue(proposedValue)
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

struct JoboptionsConsistencyIssueIndex: Sendable {
    private let affectedPaths: Set<JoboptionsKeyPath>

    init(_ issues: [JoboptionsConsistencyIssue]) {
        affectedPaths = Set(issues.map(\.path))
    }

    func affects(_ path: JoboptionsKeyPath) -> Bool {
        affectedPaths.contains(path)
    }

    func affects(any paths: [JoboptionsKeyPath]) -> Bool {
        paths.contains(where: affectedPaths.contains)
    }
}

typealias GhostscriptCompatibilityIssue = JoboptionsConsistencyIssue
