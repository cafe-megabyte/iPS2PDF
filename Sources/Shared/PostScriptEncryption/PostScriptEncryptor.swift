import Foundation
import UniformTypeIdentifiers

enum PostScriptEncryptor {
    static var supportedContentTypes: [UTType] {
        ["ps", "eps"].compactMap { UTType(filenameExtension: $0) }
    }

    static func outputFilename(for sourceName: String) -> String {
        let stem = URL(fileURLWithPath: sourceName)
            .deletingPathExtension()
            .lastPathComponent
        return (stem.isEmpty ? "PostScript" : stem) + ".encrypted.ps"
    }

    static func validatePassword(_ password: String) throws {
        let result = Int(password.withCString(psencrypt_validate_password))
        guard result == PSENCRYPT_SUCCESS else {
            throw error(for: result)
        }
    }

    static func validateInput(at url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        } catch {
            throw PostScriptEncryptionError.inputCannotBeRead
        }
        guard values.isRegularFile == true,
              FileManager.default.isReadableFile(atPath: url.path)
        else {
            throw PostScriptEncryptionError.inputCannotBeRead
        }

        let extensionIsPostScript = ["ps", "eps"].contains(url.pathExtension.lowercased())
        if extensionIsPostScript { return }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            guard try handle.read(upToCount: 4) == Data("%!PS".utf8) else {
                throw PostScriptEncryptionError.inputIsNotPostScript
            }
        } catch let error as PostScriptEncryptionError {
            throw error
        } catch {
            throw PostScriptEncryptionError.inputCannotBeRead
        }
    }

    static func encrypt(inputURL: URL, outputURL: URL, password: String) throws {
        try validatePassword(password)
        let access = inputURL.startAccessingSecurityScopedResource()
        defer { if access { inputURL.stopAccessingSecurityScopedResource() } }
        let result = Int(inputURL.path.withCString { inputPath in
            outputURL.path.withCString { outputPath in
                password.withCString { passwordPointer in
                    psencrypt_encrypt_postscript(inputPath, outputPath, passwordPointer)
                }
            }
        })
        guard result == PSENCRYPT_SUCCESS else {
            throw error(for: result)
        }
    }

    private static func error(for result: Int) -> PostScriptEncryptionError {
        switch result {
        case PSENCRYPT_PASSWORD_EMPTY: .passwordEmpty
        case PSENCRYPT_PASSWORD_TOO_LONG: .passwordTooLong
        case PSENCRYPT_PASSWORD_UNSUPPORTED_CHARACTER: .unsupportedPasswordCharacter
        case PSENCRYPT_PASSWORD_RESERVED: .reservedPassword
        case PSENCRYPT_INPUT_OPEN_FAILED: .inputCannotBeRead
        case PSENCRYPT_INPUT_NOT_POSTSCRIPT: .inputIsNotPostScript
        case PSENCRYPT_OUTPUT_EXISTS: .outputAlreadyExists
        case PSENCRYPT_OUTPUT_OPEN_FAILED: .outputCannotBeCreated
        case PSENCRYPT_RANDOM_FAILED: .randomGenerationFailed
        case PSENCRYPT_KEY_DERIVATION_FAILED: .keyDerivationFailed
        case PSENCRYPT_CRYPTO_FAILED: .encryptionFailed
        case PSENCRYPT_READ_FAILED: .inputReadFailed
        case PSENCRYPT_WRITE_FAILED: .outputWriteFailed
        default: .invalidArgument
        }
    }
}
