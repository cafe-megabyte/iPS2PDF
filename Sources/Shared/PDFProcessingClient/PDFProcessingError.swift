import Foundation

enum PDFProcessingError: LocalizedError {
    case passwordRequired, invalidReply, failed, busy, limitExceeded
    case conformityUnsupported(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired: String(localized: "Enter the PDF opening password.")
        case .invalidReply: String(localized: "The PDF helper returned an invalid result.")
        case .failed: String(localized: "The PDF could not be processed. The original is unchanged.")
        case .busy: String(localized: "Another PDF operation is already running. Try again when it finishes.")
        case .limitExceeded: String(localized: "PDF processing exceeded its time or resource limit.")
        case .conformityUnsupported(let reason):
            String(localized: "The declared PDF conformity cannot safely be preserved.") +
                (reason.isEmpty ? "" : "\n\n" + NSLocalizedString(reason, comment: "Native conformity diagnostic"))
        case .unsupported(let reason):
            String(localized: "This PDF contains a feature that cannot yet be processed safely. The original is unchanged.") +
                (reason.isEmpty ? "" : "\n\n" + NSLocalizedString(reason, comment: "Native processing diagnostic"))
        }
    }
}
