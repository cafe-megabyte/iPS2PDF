import Foundation

enum PDFStandard: String, CaseIterable, Identifiable, Sendable {
    case none
    case pdfa1b
    case pdfa2b
    case pdfa3b
    case pdfx1
    case pdfx3
    case pdfx4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .pdfa1b: "PDF/A-1b"
        case .pdfa2b: "PDF/A-2b"
        case .pdfa3b: "PDF/A-3b"
        case .pdfx1: "PDF/X-1"
        case .pdfx3: "PDF/X-3"
        case .pdfx4: "PDF/X-4"
        }
    }

    var requiredCompatibilityLevel: String? {
        switch self {
        case .none: nil
        case .pdfa1b, .pdfx1, .pdfx3: "1.4"
        case .pdfa2b, .pdfa3b, .pdfx4: "1.7"
        }
    }

    var ghostscriptPDFAValue: String? {
        switch self {
        case .pdfa1b: "1"
        case .pdfa2b: "2"
        case .pdfa3b: "3"
        default: nil
        }
    }

    var ghostscriptPDFXValue: String? {
        switch self {
        case .pdfx1: "1"
        case .pdfx3: "3"
        case .pdfx4: "4"
        default: nil
        }
    }
}
