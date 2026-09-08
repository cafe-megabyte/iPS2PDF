import Foundation

struct PDFCompressionOptions: Codable, Equatable, Sendable {
    enum Level: Int, CaseIterable, Codable, Sendable {
        case gentle, balanced, strong

        var title: String {
            switch self {
            case .gentle: String(localized: "Gentle")
            case .balanced: String(localized: "Balanced")
            case .strong: String(localized: "Strong")
            }
        }
    }

    enum ColorMode: String, CaseIterable, Codable, Sendable {
        case color, blackAndWhite

        var title: String {
            switch self {
            case .color: String(localized: "Color")
            case .blackAndWhite: String(localized: "Black & White")
            }
        }
    }

    var level: Level = .balanced
    var colorMode: ColorMode = .color
    var threshold: Int = 75
    // Color scans usually benefit from modest contrast expansion.
    var contrast: Int = 25

    var isValid: Bool { (0...100).contains(threshold) && (0...100).contains(contrast) }
}
