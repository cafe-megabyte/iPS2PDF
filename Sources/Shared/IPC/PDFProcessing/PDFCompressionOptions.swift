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
    // Paper cleanup controls background normalization and content separation.
    var paperCleanup: Int = 50
    // An optional sampled page area identifies removable paper colors without
    // changing the automatic behavior for ordinary documents.
    var paperSample: PDFPaperSample?

    var isValid: Bool {
        (0...100).contains(threshold) && (0...100).contains(contrast) &&
            (0...100).contains(paperCleanup) && (paperSample?.isValid ?? true)
    }
}
