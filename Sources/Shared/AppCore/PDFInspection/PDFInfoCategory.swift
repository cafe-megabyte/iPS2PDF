import Foundation

enum PDFInfoCategory: String, CaseIterable, Identifiable, Sendable {
    case overview, fonts, colors, security, pages, contents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .fonts: String(localized: "Fonts")
        case .colors: String(localized: "Colors")
        case .security: String(localized: "Security")
        case .pages: String(localized: "Pages")
        case .contents: String(localized: "Contents")
        }
    }
    var symbol: String {
        switch self {
        case .overview: "doc.text"
        case .fonts: "textformat"
        case .colors: "paintpalette"
        case .security: "lock"
        case .pages: "doc.on.doc"
        case .contents: "square.stack.3d.up"
        }
    }
}
