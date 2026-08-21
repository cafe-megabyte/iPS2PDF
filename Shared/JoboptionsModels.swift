import Foundation

enum JoboptionsOrigin: String, Codable, Sendable {
    case bundled
    case user
}

struct JoboptionsRecord: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let origin: JoboptionsOrigin
    let url: URL

    var isBundled: Bool { origin == .bundled }
}

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

enum JoboptionsValue: Equatable, Sendable {
    case boolean(Bool)
    case number(Double, original: String)
    case name(String)
    case string(String)
    case array([JoboptionsValue])
    case dictionary([String: JoboptionsValue])
    case raw(String)

    var boolValue: Bool? {
        guard case let .boolean(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value, _) = self else { return nil }
        return value
    }

    var textualValue: String? {
        switch self {
        case let .name(value), let .string(value), let .raw(value): value
        case let .number(_, original): original
        case let .boolean(value): value ? "true" : "false"
        case .array, .dictionary: nil
        }
    }

    var postScript: String {
        switch self {
        case let .boolean(value):
            return value ? "true" : "false"
        case let .number(_, original):
            return original
        case let .name(value):
            return "/\(value)"
        case let .string(value):
            return "(\(Self.escapeLiteralString(value)))"
        case let .array(values):
            return "[\(values.map(\.postScript).joined(separator: " "))]"
        case let .dictionary(values):
            let body = values.sorted { $0.key < $1.key }
                .map { "/\($0.key) \($0.value.postScript)" }
                .joined(separator: " ")
            return "<< \(body) >>"
        case let .raw(value):
            return value
        }
    }

    private static func escapeLiteralString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }
}

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
