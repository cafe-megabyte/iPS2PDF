import Foundation

enum PDFProcessingWarning: String, Codable, Sendable, Identifiable {
    case signaturesRemoved
    case protectionRemoved
    case conformityRemoved
    case attachmentsRemoved
    case signatureAppearanceMayDiffer

    var id: String { rawValue }

    var message: String {
        switch self {
        case .signaturesRemoved:
            String(localized: "Digital signatures were removed. Review the result before saving.")
        case .protectionRemoved:
            String(localized: "The original protection could not be preserved and was removed. Review the result before saving.")
        case .conformityRemoved:
            String(localized: "The result no longer claims the original PDF conformity.")
        case .attachmentsRemoved:
            String(localized: "Embedded files were removed. This also removes embedded invoice data such as ZUGFeRD.")
        case .signatureAppearanceMayDiffer:
            String(localized: "Some signature appearances could not be preserved consistently across PDF readers.")
        }
    }
}
