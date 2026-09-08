import Foundation

enum PDFExtractableResourceFormat: String, Codable, Hashable, Sendable {
    case embeddedFile
    case jpeg
    case jpeg2000
    case png
    case type1
    case trueType
    case trueTypeCollection
    case cff
    case openType
    case openTypeCollection
    case icc
    case xml

    var pathExtension: String {
        switch self {
        case .embeddedFile: ""
        case .jpeg: "jpg"
        case .jpeg2000: "jp2"
        case .png: "png"
        case .type1: "pfb"
        case .trueType: "ttf"
        case .trueTypeCollection: "ttc"
        case .cff: "cff"
        case .openType: "otf"
        case .openTypeCollection: "otc"
        case .icc: "icc"
        case .xml: "xml"
        }
    }
}
