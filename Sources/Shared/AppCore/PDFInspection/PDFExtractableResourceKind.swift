import Foundation

enum PDFExtractableResourceKind: String, Codable, Hashable, Sendable {
    case attachment
    case image
    case font
    case iccProfile
    case xmpMetadata

    var folderName: String {
        switch self {
        case .attachment: "Attachments"
        case .image: "Images"
        case .font: "Fonts"
        case .iccProfile: "ICC Profiles"
        case .xmpMetadata: "Metadata"
        }
    }

    var accessibilityName: String {
        switch self {
        case .attachment: String(localized: "attachment")
        case .image: String(localized: "image")
        case .font: String(localized: "font")
        case .iccProfile: String(localized: "ICC profile")
        case .xmpMetadata: String(localized: "XMP metadata")
        }
    }
}
