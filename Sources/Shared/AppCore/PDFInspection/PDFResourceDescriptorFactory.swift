import CoreGraphics
import CryptoKit
import Foundation

enum PDFResourceDescriptorFactory {
    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sanitizedName(_ value: String, fallback: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        let cleaned = value.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return fallback }
        return String(cleaned.prefix(180))
    }

    static func filename(base: String, format: PDFExtractableResourceFormat,
                         fallback: String, subset: Bool = false) -> String {
        var name = sanitizedName(base, fallback: fallback)
        let currentExtension = URL(fileURLWithPath: name).pathExtension
        let knownExtensions = ["pfb", "ttf", "ttc", "cff", "otf", "otc", "icc", "icm", "xml", "jpg", "jpeg", "jp2", "png"]
        if knownExtensions.contains(currentExtension.lowercased()) { name = String(name.dropLast(currentExtension.count + 1)) }
        if subset, !name.localizedCaseInsensitiveContains("subset") { name += "-subset" }
        return format.pathExtension.isEmpty ? name : name + "." + format.pathExtension
    }

    static func attachment(_ dictionary: CGPDFDictionaryRef) -> PDFExtractableResource? {
        guard let embedded = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "EF")) else { return nil }
        let preferredKeys = ["UF", "F", "Unix", "Mac", "DOS"]
        guard let stream = preferredKeys.lazy.compactMap({ PDFObjectReader.stream(PDFObjectReader.object(embedded, $0)) }).first,
              let data = PDFObjectReader.data(stream) else { return nil }
        let originalName = PDFObjectReader.text(dictionary, "UF") ?? PDFObjectReader.text(dictionary, "F") ?? String(localized: "Attachment")
        let safeName = sanitizedName(originalName, fallback: "Attachment")
        let digest = fingerprint(data)
        return PDFExtractableResource(fingerprint: digest, kind: .attachment, format: .embeddedFile,
                                      suggestedFilename: safeName, identityQualifier: safeName)
    }

    static func xmp(_ data: Data, baseName: String = "Metadata") -> PDFExtractableResource {
        PDFExtractableResource(fingerprint: fingerprint(data), kind: .xmpMetadata, format: .xml,
                               suggestedFilename: filename(base: baseName, format: .xml, fallback: "Metadata"))
    }

    static func icc(_ data: Data, name: String) -> PDFExtractableResource {
        PDFExtractableResource(fingerprint: fingerprint(data), kind: .iccProfile, format: .icc,
                               suggestedFilename: filename(base: name, format: .icc, fallback: "ICC Profile"))
    }

    static func font(stream: CGPDFStreamRef, key: String, fontName: String,
                     subset: Bool) -> PDFExtractableResource? {
        guard let data = PDFObjectReader.data(stream), !data.isEmpty else { return nil }
        let dictionary = CGPDFStreamGetDictionary(stream)
        let subtype = PDFObjectReader.name(dictionary, "Subtype")
        guard let format = fontProgramFormat(data, key: key, subtype: subtype) else { return nil }
        let base = filename(base: fontName, format: format, fallback: "Embedded Font", subset: subset)
        return PDFExtractableResource(fingerprint: fingerprint(data), kind: .font, format: format,
                                      suggestedFilename: base, pixelWidth: nil, pixelHeight: nil,
                                      bitsPerComponent: nil, isFontSubset: subset)
    }

    static func fontProgramFormat(_ data: Data, key: String, subtype: String?) -> PDFExtractableResourceFormat? {
        if key == "FontFile" {
            return .type1
        } else if key == "FontFile2" {
            return sfntFormat(data) ?? .trueType
        } else if subtype == "Type1C" || subtype == "CIDFontType0C" {
            return sfntFormat(data) ?? (canWrapCFFAsOpenType(data) ? .openType : .cff)
        } else if subtype == "OpenType" {
            return sfntFormat(data) ?? (canWrapCFFAsOpenType(data) ? .openType : .cff)
        }
        return nil
    }

    static func image(_ stream: CGPDFStreamRef, fallbackIndex: Int = 0) -> PDFExtractableResource? {
        guard let payload = PDFObjectReader.streamData(stream), !payload.data.isEmpty else { return nil }
        let dictionary = CGPDFStreamGetDictionary(stream)
        let width = PDFObjectReader.integer(dictionary, "Width") ?? PDFObjectReader.integer(dictionary, "W")
        let height = PDFObjectReader.integer(dictionary, "Height") ?? PDFObjectReader.integer(dictionary, "H")
        let bits = PDFObjectReader.integer(dictionary, "BitsPerComponent") ?? PDFObjectReader.integer(dictionary, "BPC")
        let hasMask = PDFObjectReader.object(dictionary, "SMask") != nil || PDFObjectReader.object(dictionary, "Mask") != nil
        let hasCustomDecode = PDFObjectReader.object(dictionary, "Decode") != nil || PDFObjectReader.object(dictionary, "D") != nil
        let format: PDFExtractableResourceFormat = if !hasMask && !hasCustomDecode && payload.format == .jpegEncoded {
            .jpeg
        } else if !hasMask && !hasCustomDecode && payload.format == .JPEG2000 {
            .jpeg2000
        } else {
            .png
        }
        let digest = fingerprint(payload.data)
        let dimensions = [width, height, bits].map { $0.map(String.init) ?? "-" }.joined(separator: "x")
        let base = fallbackIndex > 0 ? "Image-\(fallbackIndex)" : "Image-" + String(digest.prefix(10))
        return PDFExtractableResource(fingerprint: digest, kind: .image, format: format,
                                      suggestedFilename: filename(base: base, format: format, fallback: "Image"),
                                      identityQualifier: dimensions, pixelWidth: width,
                                      pixelHeight: height, bitsPerComponent: bits)
    }

    static func sfntFormat(_ data: Data) -> PDFExtractableResourceFormat? {
        if let collection = collectionFormat(data) { return collection }
        guard data.count >= 4 else { return nil }
        if data.starts(with: Array("OTTO".utf8)) { return .openType }
        if data.starts(with: [0x00, 0x01, 0x00, 0x00]) { return .trueType }
        return nil
    }

    private static func collectionFormat(_ data: Data) -> PDFExtractableResourceFormat? {
        guard data.count >= 16, data.starts(with: Array("ttcf".utf8)) else { return nil }
        let offset = data[12..<16].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard offset <= UInt32(Int.max), Int(offset) + 4 <= data.count else { return .trueType }
        return data[Int(offset)..<(Int(offset) + 4)].elementsEqual("OTTO".utf8) ? .openTypeCollection : .trueTypeCollection
    }

    static func canWrapCFFAsOpenType(_ data: Data) -> Bool {
        guard data.count >= 4, data[data.startIndex] == 1,
              data[data.startIndex + 2] >= 4,
              Int(data[data.startIndex + 2]) <= data.count,
              (1...4).contains(data[data.startIndex + 3]),
              Int(data[data.startIndex + 2]) + 2 <= data.count,
              data[data.startIndex + Int(data[data.startIndex + 2])] == 0,
              data[data.startIndex + Int(data[data.startIndex + 2]) + 1] == 1,
              let provider = CGDataProvider(data: data as CFData),
              let font = CGFont(provider),
              (1...Int(UInt16.max)).contains(font.numberOfGlyphs),
              (16...16_384).contains(font.unitsPerEm) else { return false }
        return true
    }
}
