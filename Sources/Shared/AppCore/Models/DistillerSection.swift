import Foundation

enum DistillerSection: String, Sendable {
    case description
    case fileOptions
    case pageRange
    case pageSize
    case colorImages
    case grayscaleImages
    case monochromeImages
    case imagePolicies
    case fontEmbedding
    case colorSettings
    case colorManagement
    case workingSpaces
    case deviceDependentColor
    case advancedOptions
    case dsc
    case conformance
    case pageBoxes
    case outputIntent
    case preserved
    case originalSource
    case application

    var title: String {
        switch self {
        case .description: String(localized: "Description")
        case .fileOptions: String(localized: "File options")
        case .pageRange: String(localized: "Page range")
        case .pageSize: String(localized: "Default page size")
        case .colorImages: String(localized: "Color images")
        case .grayscaleImages: String(localized: "Grayscale images")
        case .monochromeImages: String(localized: "Monochrome images")
        case .imagePolicies: String(localized: "Image policies")
        case .fontEmbedding: String(localized: "Font embedding")
        case .colorSettings: String(localized: "Color settings")
        case .colorManagement: String(localized: "Color management")
        case .workingSpaces: String(localized: "Working spaces")
        case .deviceDependentColor: String(localized: "Device-dependent data")
        case .advancedOptions: String(localized: "Options")
        case .dsc: "DSC"
        case .conformance: String(localized: "Standards compliance")
        case .pageBoxes: String(localized: "Page boxes")
        case .outputIntent: String(localized: "Output intent")
        case .preserved: String(localized: "Preserved settings")
        case .originalSource: String(localized: "Original source")
        case .application: "iPS2PDF"
        }
    }
}
