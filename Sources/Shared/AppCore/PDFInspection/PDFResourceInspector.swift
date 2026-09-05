import CoreGraphics
import Foundation

final class PDFResourceInspector {
    private(set) var sections: [String: PDFInfoSection] = [:]
    private var locations: [String: Set<String>] = [:]
    private var fontPages: [String: Set<Int>] = [:]
    private var usedFontPages: [String: Set<Int>] = [:]
    private var missingFonts: Set<String> = []
    private var visited: Set<UInt> = []
    private(set) var limited = false
    private var objectCount = 0

    func inspect(_ object: CGPDFObjectRef?, location: String, page: Int = 0, depth: Int = 0) {
        guard let object else { return }
        guard depth < 64, objectCount < 200_000, !Task.isCancelled else { limited = true; return }
        objectCount += 1
        if let array = PDFObjectReader.array(object) {
            for (i, value) in PDFObjectReader.elements(array).enumerated() { inspect(value, location: location + "/\(i + 1)", page: page, depth: depth + 1) }
            return
        }
        guard let dictionary = PDFObjectReader.dictionary(object) else { return }
        let identity = UInt(bitPattern: dictionary.rawValue)
        if PDFObjectReader.name(dictionary, "Type") == "Font" || ["Type1", "MMType1", "TrueType", "Type0", "Type3"].contains(PDFObjectReader.name(dictionary, "Subtype") ?? "") {
            font(dictionary, location: location, page: page)
        }
        guard !visited.contains(identity) else { return }
        visited.insert(identity)
        defer { visited.remove(identity) }
        if let stream = PDFObjectReader.stream(object) {
            if PDFObjectReader.name(dictionary, "Subtype") == "Image" { image(stream, location: location) }
            if PDFObjectReader.name(dictionary, "Type") == "EmbeddedFile" {
                store(PDFInfoSection(id: "embedded-file-\(identity)", category: .contents, title: String(localized: "Embedded file properties"), fields: PDFObjectReader.fields(dictionary), initiallyExpanded: false), location: location)
            }
            if PDFObjectReader.name(dictionary, "Subtype") == "XML" {
                let data = PDFObjectReader.data(stream)
                let readable = data.map { PDFXMPReader(data: $0).isValid } ?? false
                if !readable { limited = true }
                store(PDFInfoSection(id: "metadata-\(identity)", category: .overview, title: String(localized: "Object metadata"), fields: [PDFInfoField("XMP", data.map(Self.xmlText) ?? PDFInspectionFormat.unknown)], initiallyExpanded: false, isComplete: readable), location: location)
            }
        }
        if PDFObjectReader.name(dictionary, "Type") == "OutputIntent" || PDFObjectReader.object(dictionary, "DestOutputProfile") != nil {
            store(PDFInfoSection(id: "intent-\(identity)", category: .colors, title: String(localized: "Output intent"), fields: PDFObjectReader.fields(dictionary, excluding: ["DestOutputProfile"])), location: location)
        }
        if let type = inheritedFieldValue(dictionary, "FT"),
           ["FT", "T", "Kids", "V"].contains(where: { PDFObjectReader.object(dictionary, $0) != nil }) {
            let isSignature = PDFObjectReader.describe(type) == "Sig"
            var fields = PDFObjectReader.fields(dictionary, excluding: ["Parent", "Kids", "AP", "P", "V"])
            for key in ["FT", "Ff", "DV", "DA", "Q", "MaxLen", "Opt", "TI", "I"] where PDFObjectReader.object(dictionary, key) == nil {
                if let value = inheritedFieldValue(dictionary, key) { fields.append(PDFInfoField(key + " (" + String(localized: "Inherited") + ")", PDFObjectReader.describe(value))) }
            }
            let value = inheritedFieldValue(dictionary, "V")
            if isSignature { fields.append(PDFInfoField("Signature value present (not validated)", PDFInspectionFormat.yesNo(PDFObjectReader.dictionary(value) != nil))) }
            else if let value { fields.append(PDFInfoField("V", PDFObjectReader.describe(value))) }
            store(PDFInfoSection(id: "field-\(identity)", category: isSignature ? .security : .contents, title: String(localized: "Form field") + " · " + fieldName(dictionary), fields: fields), location: location)
        }
        if PDFObjectReader.name(dictionary, "Type") == "Sig" || PDFObjectReader.object(dictionary, "ByteRange") != nil {
            store(PDFInfoSection(id: "signature-\(identity)", category: .security, title: String(localized: "Signature (not validated)"), fields: PDFObjectReader.fields(dictionary, excluding: ["Contents", "Cert"])) , location: location)
        }
        if PDFObjectReader.name(dictionary, "Type") == "Filespec" || PDFObjectReader.object(dictionary, "EF") != nil {
            store(PDFInfoSection(id: "attachment-\(identity)", category: .contents, title: String(localized: "Attachment") + " · " + (PDFObjectReader.text(dictionary, "UF") ?? PDFObjectReader.text(dictionary, "F") ?? "—"), fields: PDFObjectReader.fields(dictionary, excluding: ["EF"])), location: location)
        }
        if PDFObjectReader.name(dictionary, "Type") == "Annot" || PDFObjectReader.object(dictionary, "Rect") != nil && PDFObjectReader.object(dictionary, "Subtype") != nil {
            store(PDFInfoSection(id: "annotation-\(identity)", category: .contents, title: String(localized: "Annotation") + " · " + (PDFObjectReader.name(dictionary, "Subtype") ?? "—"), fields: PDFObjectReader.fields(dictionary, excluding: ["P", "Parent", "AP"]), initiallyExpanded: false), location: location)
        }
        if PDFObjectReader.object(dictionary, "JS") != nil || PDFObjectReader.name(dictionary, "Type") == "Action" || ["GoTo", "GoToR", "GoToE", "Launch", "Thread", "URI", "Sound", "Movie", "Hide", "Named", "SubmitForm", "ResetForm", "ImportData", "JavaScript", "SetOCGState", "Rendition", "Trans", "GoTo3DView"].contains(PDFObjectReader.name(dictionary, "S") ?? "") {
            var fields = PDFObjectReader.fields(dictionary, excluding: ["JS", "Next"])
            if let js = PDFObjectReader.object(dictionary, "JS") {
                let value = PDFObjectReader.stream(js).flatMap(PDFObjectReader.data).map { String(decoding: $0, as: UTF8.self) } ?? PDFObjectReader.describe(js)
                fields.append(PDFInfoField("JavaScript (not executed)", value))
            }
            store(PDFInfoSection(id: "action-\(identity)", category: .contents, title: String(localized: "Document action"), fields: fields, initiallyExpanded: false), location: location)
        }
        for (key, value) in PDFObjectReader.pairs(dictionary) {
            if ["Parent", "P", "Prev", "Pages", "Contents", "FontFile", "FontFile2", "FontFile3"].contains(key) { continue }
            if key == "DestOutputProfile", let stream = PDFObjectReader.stream(value) { profile(stream, location: location + "/" + key) }
            if ["ColorSpace", "CS"].contains(key) {
                store(PDFInfoSection(id: "colorspace-\(identity)", category: .colors, title: String(localized: "Color space"), fields: [PDFInfoField("Definition", PDFObjectReader.describe(value))]), location: location)
                colorProfiles(value, location: location + "/" + key)
            }
            if key == "ExtGState" || key == "Group" || key == "OCProperties" || key == "MarkInfo" {
                store(PDFInfoSection(id: "property-\(identity)-\(key)", category: key == "ExtGState" || key == "Group" ? .colors : .contents, title: key, fields: [PDFInfoField("Definition", PDFObjectReader.describe(value))], initiallyExpanded: false), location: location)
            }
            inspect(value, location: location + "/" + key, page: page, depth: depth + 1)
        }
    }

    func markUsedFonts(_ identities: Set<UInt>, page: Int) {
        for identity in identities { usedFontPages["font-\(identity)", default: []].insert(page) }
    }
    func addScannedColors(_ scanner: PDFContentScanner, page: Int) {
        for space in scanner.colorSpaces.sorted() {
            store(PDFInfoSection(id: "content-color-" + space, category: .colors, title: String(localized: "Color space used in content"), fields: [PDFInfoField("Definition", space)]), location: "\(String(localized: "Page")) \(page)")
        }
    }
    func addScannedImages(_ scanner: PDFContentScanner, page: Int) {
        for image in scanner.images {
            let key = image.identity.hasPrefix("inline-") ? "page-\(page)-" + image.identity : image.identity
            store(PDFInfoSection(id: key, category: .contents, title: String(localized: "Image"), fields: image.fields, initiallyExpanded: false), location: "\(String(localized: "Page")) \(page)")
            // Resource enumeration may have stored the image before content scanning.
            for field in image.fields where field.label == String(localized: "Effective resolution") {
                if sections[key]?.fields.contains(where: { $0.value == field.value }) != true { sections[key]?.fields.append(field) }
            }
            if let x = image.horizontalPPI, let y = image.verticalPPI, x.isFinite, y.isFinite {
                let dpi = String(format: "%.1f × %.1f ppi", x, y)
                if sections[key]?.fields.contains(where: { $0.value == dpi }) != true {
                    sections[key]?.fields.append(PDFInfoField("Effective resolution", dpi, id: "dpi-\(page)-\(dpi)"))
                }
            }
        }
    }
    func results() -> [PDFInfoSection] {
        sections.keys.sorted().compactMap { key in
            guard var result = sections[key] else { return nil }
            result.fields.insert(PDFInfoField("Location", (locations[key] ?? []).sorted().joined(separator: "\n")), at: 0)
            if result.category == .fonts {
                let pages = usedFontPages[key] ?? []
                result.fields.insert(PDFInfoField("Used on pages", pages.isEmpty ? String(localized: "No use detected") : PDFInspectionFormat.pageList(pages)), at: 1)
                result.fields.insert(PDFInfoField("Resource on pages", PDFInspectionFormat.pageList(fontPages[key] ?? [])), at: 2)
                if !pages.isEmpty, missingFonts.contains(key) { result.warning = String(localized: "Not embedded") }
            }
            result.fields = result.fields.enumerated().map { PDFInfoField($0.element.label, $0.element.value, id: "field-\($0.offset)") }
            return result
        }
    }
    private func store(_ section: PDFInfoSection, location: String) {
        if sections[section.id] == nil { sections[section.id] = section }
        locations[section.id, default: []].insert(location)
    }
    private func font(_ dictionary: CGPDFDictionaryRef, location: String, page: Int) {
        let key = "font-\(UInt(bitPattern: dictionary.rawValue))"
        locations[key, default: []].insert(location)
        if page > 0 { fontPages[key, default: []].insert(page) }
        guard sections[key] == nil else { return }
        let subtype = PDFObjectReader.name(dictionary, "Subtype") ?? PDFInspectionFormat.unknown
        var effective = dictionary
        if subtype == "Type0", let descendant = PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(dictionary, "DescendantFonts"))).first,
           let resolved = PDFObjectReader.dictionary(descendant) { effective = resolved }
        let descriptor = PDFObjectReader.dictionary(PDFObjectReader.object(effective, "FontDescriptor"))
        let name = PDFObjectReader.name(dictionary, "BaseFont") ?? PDFObjectReader.name(descriptor, "FontName") ?? PDFObjectReader.name(dictionary, "Name") ?? subtype
        let subset = name.range(of: "^[A-Z]{6}\\+", options: .regularExpression) != nil
        let programs = ["FontFile", "FontFile2", "FontFile3"].compactMap { PDFObjectReader.stream(PDFObjectReader.object(descriptor, $0)) }
        let hasProgram = !programs.isEmpty
        let status: String
        if subtype == "Type3" { status = String(localized: "Embedded (Type 3 glyph descriptions)") }
        else if hasProgram { status = subset ? String(localized: "Embedded subset") : String(localized: "Fully embedded (PDF declaration)") }
        else if ["Type1", "MMType1", "TrueType", "Type0", "CIDFontType0", "CIDFontType2"].contains(subtype) {
            status = String(localized: "Not embedded"); missingFonts.insert(key)
        } else { status = PDFInspectionFormat.unknown }
        var fields = [PDFInfoField("Embedding", status), PDFInfoField("Font type", subtype), PDFInfoField("Subset prefix", PDFInspectionFormat.yesNo(subset))]
        fields += PDFObjectReader.fields(dictionary, excluding: ["FontDescriptor", "DescendantFonts", "Resources", "CharProcs", "Widths"])
        fields += PDFObjectReader.fields(descriptor, excluding: ["FontFile", "FontFile2", "FontFile3"])
        for (index, program) in programs.enumerated() {
            fields.append(PDFInfoField("Font program", PDFObjectReader.describeDictionary(CGPDFStreamGetDictionary(program), depth: 0, ancestors: []), id: "program-\(index)"))
        }
        // Descriptor and font dictionaries can contain the same key; retain both with distinct stable field identities.
        fields = fields.enumerated().map { PDFInfoField($0.element.label, $0.element.value, id: "field-\($0.offset)") }
        sections[key] = PDFInfoSection(id: key, category: .fonts, title: name, fields: fields)
    }
    @discardableResult private func image(_ stream: CGPDFStreamRef, location: String) -> String {
        let dictionary = CGPDFStreamGetDictionary(stream)
        let key = "image-\(UInt(bitPattern: stream.rawValue))"
        store(PDFInfoSection(id: key, category: .contents, title: String(localized: "Image"), fields: PDFObjectReader.fields(dictionary, excluding: ["SMask", "Mask", "Metadata"]), initiallyExpanded: false), location: location)
        return key
    }
    private func profile(_ stream: CGPDFStreamRef, location: String) {
        guard let data = PDFObjectReader.data(stream) else {
            limited = true
            store(PDFInfoSection(id: "unreadable-icc-\(UInt(bitPattern: stream.rawValue))", category: .colors, title: "ICC", fields: [PDFInfoField("Profile status", PDFInspectionFormat.unknown)], isComplete: false), location: location)
            return
        }
        let profile = PDFICCReader.inspect(data, location: location)
        if !profile.isComplete { limited = true }
        store(profile, location: location)
    }
    private func colorProfiles(_ object: CGPDFObjectRef, location: String, depth: Int = 0) {
        guard depth < 32 else { limited = true; return }
        if let array = PDFObjectReader.array(object) {
            let values = PDFObjectReader.elements(array)
            if values.first.map({ PDFObjectReader.describe($0) }) == "ICCBased", values.count > 1,
               let stream = PDFObjectReader.stream(values[1]) { profile(stream, location: location) }
            for value in values where PDFObjectReader.array(value) != nil { colorProfiles(value, location: location, depth: depth + 1) }
        } else if let dictionary = PDFObjectReader.dictionary(object) {
            for (key, value) in PDFObjectReader.pairs(dictionary) { colorProfiles(value, location: location + "/" + key, depth: depth + 1) }
        }
    }
    private func fieldAncestors(_ dictionary: CGPDFDictionaryRef) -> [CGPDFDictionaryRef] {
        var current: CGPDFDictionaryRef? = dictionary, result: [CGPDFDictionaryRef] = [], seen: Set<UInt> = []
        while let node = current {
            guard result.count < 64, seen.insert(UInt(bitPattern: node.rawValue)).inserted else { limited = true; break }
            result.append(node)
            current = PDFObjectReader.dictionary(PDFObjectReader.object(node, "Parent"))
        }
        return result
    }
    private func inheritedFieldValue(_ dictionary: CGPDFDictionaryRef, _ key: String) -> CGPDFObjectRef? {
        fieldAncestors(dictionary).lazy.compactMap { PDFObjectReader.object($0, key) }.first
    }
    private func fieldName(_ dictionary: CGPDFDictionaryRef) -> String {
        let parts = fieldAncestors(dictionary).reversed().compactMap { PDFObjectReader.text($0, "T") }
        return parts.isEmpty ? "—" : parts.joined(separator: ".")
    }
    static func xmlText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? PDFInspectionFormat.unknown
    }
}
