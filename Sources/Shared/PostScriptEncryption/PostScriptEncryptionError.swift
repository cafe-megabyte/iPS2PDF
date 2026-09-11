import Foundation

enum PostScriptEncryptionError: LocalizedError, Equatable {
    case invalidArgument
    case passwordEmpty
    case passwordTooLong
    case unsupportedPasswordCharacter
    case reservedPassword
    case inputCannotBeRead
    case inputIsNotPostScript
    case outputAlreadyExists
    case outputCannotBeCreated
    case randomGenerationFailed
    case keyDerivationFailed
    case encryptionFailed
    case inputReadFailed
    case outputWriteFailed

    var errorDescription: String? {
        switch self {
        case .invalidArgument:
            String(localized: "The PostScript encryption request is invalid.")
        case .passwordEmpty:
            String(localized: "Enter a password.")
        case .passwordTooLong:
            String(localized: "The password may contain at most 1,023 characters.")
        case .unsupportedPasswordCharacter:
            String(localized: "Use printable ASCII characters except parentheses and backslashes.")
        case .reservedPassword:
            String(localized: "This password is reserved. Choose a different password.")
        case .inputCannotBeRead:
            String(localized: "The selected PostScript file could not be read.")
        case .inputIsNotPostScript:
            String(localized: "The selected file is not a PostScript or EPS file.")
        case .outputAlreadyExists:
            String(localized: "The encrypted PostScript file already exists.")
        case .outputCannotBeCreated:
            String(localized: "The encrypted PostScript file could not be created.")
        case .randomGenerationFailed:
            String(localized: "Secure random data could not be generated.")
        case .keyDerivationFailed:
            String(localized: "The encryption key could not be derived.")
        case .encryptionFailed:
            String(localized: "The PostScript file could not be encrypted.")
        case .inputReadFailed:
            String(localized: "The PostScript file could not be read completely.")
        case .outputWriteFailed:
            String(localized: "The encrypted PostScript file could not be written completely.")
        }
    }
}
