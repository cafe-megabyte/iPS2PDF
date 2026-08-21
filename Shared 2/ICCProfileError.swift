import Foundation

enum ICCProfileError: LocalizedError {
    case invalidHeader

    var errorDescription: String? {
        String(localized: "The file does not contain a valid ICC profile header.")
    }
}
