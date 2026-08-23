import Foundation

enum JoboptionsError: LocalizedError, Sendable {
    case empty
    case tooLarge
    case unsupportedEncoding
    case malformed(String)
    case missingDistillerDictionary
    case unreadable
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "The Joboptions file is empty.")
        case .tooLarge:
            String(localized: "The Joboptions file is larger than 16 MB.")
        case .unsupportedEncoding:
            String(localized: "The Joboptions encoding is not supported.")
        case let .malformed(detail):
            String(
                format: String(localized: "The Joboptions structure is malformed: %@"),
                locale: .current,
                detail
            )
        case .missingDistillerDictionary:
            String(localized: "The file does not contain a static Distiller parameter dictionary.")
        case .unreadable:
            String(localized: "The Joboptions file cannot be read.")
        case .writeFailed:
            String(localized: "The Joboptions file could not be saved.")
        }
    }
}
