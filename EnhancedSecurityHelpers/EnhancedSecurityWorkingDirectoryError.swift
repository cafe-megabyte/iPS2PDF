import Foundation

enum EnhancedSecurityWorkingDirectoryError: LocalizedError {
    case noWritableDirectory([String])

    var errorDescription: String? {
        switch self {
        case .noWritableDirectory(let failures):
            return "No writable Enhanced Security helper work directory. \(failures.joined(separator: " | "))"
        }
    }
}
