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

struct PDFExtractableResource: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let fingerprint: String
    let kind: PDFExtractableResourceKind
    let format: PDFExtractableResourceFormat
    let suggestedFilename: String
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil
    var bitsPerComponent: Int? = nil
    var isFontSubset = false

    init(fingerprint: String, kind: PDFExtractableResourceKind,
         format: PDFExtractableResourceFormat, suggestedFilename: String,
         identityQualifier: String = "", pixelWidth: Int? = nil,
         pixelHeight: Int? = nil, bitsPerComponent: Int? = nil,
         isFontSubset: Bool = false) {
        self.fingerprint = fingerprint
        self.kind = kind
        self.format = format
        self.suggestedFilename = suggestedFilename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bitsPerComponent = bitsPerComponent
        self.isFontSubset = isFontSubset
        id = [kind.rawValue, fingerprint, identityQualifier].filter { !$0.isEmpty }.joined(separator: ":")
    }
}
