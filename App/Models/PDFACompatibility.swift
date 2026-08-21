import Foundation

enum PDFACompatibility: String, CaseIterable, Identifiable, Sendable {
    case none
    case pdfa1b
    case pdfa2b
    case pdfa3b

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            String(localized: "pdfa_compatibility_none_title")
        case .pdfa1b:
            String(localized: "pdfa_compatibility_1b_title")
        case .pdfa2b:
            String(localized: "pdfa_compatibility_2b_title")
        case .pdfa3b:
            String(localized: "pdfa_compatibility_3b_title")
        }
    }

    var detail: String? {
        switch self {
        case .none:
            nil
        case .pdfa1b:
            String(localized: "pdfa_compatibility_1b_detail")
        case .pdfa2b:
            String(localized: "pdfa_compatibility_2b_detail")
        case .pdfa3b:
            String(localized: "pdfa_compatibility_3b_detail")
        }
    }

    var requiredPDFVersion: PDFVersion? {
        switch self {
        case .none:
            nil
        case .pdfa1b:
            .v14
        case .pdfa2b, .pdfa3b:
            .v17
        }
    }

    var isHighlighted: Bool {
        self == .none
    }

    var ghostscriptPDFAValue: String? {
        switch self {
        case .none:
            nil
        case .pdfa1b:
            "1"
        case .pdfa2b:
            "2"
        case .pdfa3b:
            "3"
        }
    }
}
