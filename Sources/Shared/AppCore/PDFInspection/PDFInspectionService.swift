import CoreGraphics
import Foundation
import PDFKit

enum PDFInspectionService {
    static func inspect(url: URL, fileName: String, password: String?, fileDates: (created: Date?, modified: Date?)? = nil, progress: @Sendable (PDFInspectionReport) -> Void = { _ in }) throws -> PDFInspectionReport {
        var report = PDFInspectionReport(fileName: fileName)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        report.sections.append(PDFInfoSection(id: "file", category: .overview, title: String(localized: "File"), fields: [
            PDFInfoField("File name", fileName), PDFInfoField("File size", PDFInspectionFormat.size(Int64(values.fileSize ?? 0)))
        ]))
        // Keep independent readers: PDFKit can reject a Unicode password that
        // Core Graphics accepts, and a failed PDFKit unlock relocks its documentRef.
        guard let pdf = PDFDocument(url: url), let document = CGPDFDocument(url as CFURL) else { throw CocoaError(.fileReadCorruptFile) }
        if document.isEncrypted && !document.isUnlocked { _ = document.unlockWithPassword(password ?? "") }
        if pdf.isLocked, let password { _ = pdf.unlock(withPassword: password) }
        report.isLocked = !document.isUnlocked
        report.sections.append(security(document))
        if document.isEncrypted, document.isUnlocked, let details = PDFEncryptionReader.inspect(url: url, password: password) {
            report.sections.append(PDFInfoSection(id: "encryption", category: .security, title: String(localized: "Encryption dictionary and declared permissions"), fields: details.fields, isComplete: details.isComplete))
            if !details.isComplete { report.notices.append(String(localized: "The encryption dictionary could not be read completely.")) }
        }
        if report.isLocked {
            report.notices = [String(localized: "Password required. Protected properties are not yet readable.")]
            return report
        }
        if document.isEncrypted, !report.sections.contains(where: { $0.id == "encryption" }) {
            report.sections.append(PDFInfoSection(id: "encryption", category: .security, title: String(localized: "Encryption dictionary and declared permissions"), fields: [PDFInfoField("Encryption details", PDFInspectionFormat.unknown)]))
            report.notices.append(String(localized: "The encryption dictionary could not be read completely."))
        }
        let catalog = document.catalog
        var major: Int32 = 0, minor: Int32 = 0
        document.getVersion(majorVersion: &major, minorVersion: &minor)
        let headerVersion = "\(major).\(minor)"
        let override = PDFObjectReader.name(catalog, "Version")
        report.pageCount = document.numberOfPages
        report.sections[0].fields += [PDFInfoField("PDF version", effectiveVersion(header: headerVersion, catalog: override)), PDFInfoField("Header version", headerVersion), PDFInfoField("Page count", String(report.pageCount))]
        if let override { report.sections[0].fields.append(PDFInfoField("Catalog version", override)) }
        if PDFObjectReader.object(catalog, "Version") != nil, override.flatMap(versionParts) == nil {
            report.notices.append(String(localized: "The catalog PDF version could not be interpreted."))
        }
        var documentFields: [PDFInfoField] = []
        let labels = ["Title": "Title", "Subject": "Subject", "Author": "Author", "Keywords": "Keywords", "Creator": "Creation application", "Producer": "PDF producer", "CreationDate": "Created", "ModDate": "Modified", "Trapped": "Trapped"]
        for key in ["Title", "Subject", "Author", "Keywords", "Creator", "Producer", "CreationDate", "ModDate", "Trapped"] {
            var value = PDFObjectReader.text(document.info, key) ?? PDFInspectionFormat.absent
            if let date = pdf.documentAttributes?[PDFDocumentAttribute(rawValue: key)] as? Date { value = PDFInspectionFormat.date(date) }
            documentFields.append(PDFInfoField(labels[key] ?? key, value))
        }
        documentFields.append(PDFInfoField("Language", PDFObjectReader.text(catalog, "Lang") ?? PDFInspectionFormat.absent))
        report.sections.append(PDFInfoSection(id: "document", category: .overview, title: String(localized: "Document"), fields: documentFields))
        var declarations: [String] = []
        for key in ["GTS_PDFXVersion", "GTS_PDFXConformance", "GTS_PDFA1Version"] {
            if let value = PDFObjectReader.text(document.info, key) { declarations.append(value + " (Info)") }
        }
        let metadataObject = PDFObjectReader.object(catalog, "Metadata")
        let metadataData = PDFObjectReader.stream(metadataObject).flatMap(PDFObjectReader.data)
        var standardMetadataReadable = true
        var hasConflictingStandardMetadata = false
        if metadataObject != nil, metadataData == nil {
            standardMetadataReadable = false
            report.notices.append(String(localized: "XMP metadata is present but could not be decoded."))
            report.sections.append(PDFInfoSection(id: "xmp", category: .overview, title: String(localized: "XMP metadata"), fields: [PDFInfoField("XMP", PDFInspectionFormat.unknown)], initiallyExpanded: false, isComplete: false))
        }
        if let data = metadataData {
            var metadataData = data
            var xmp = PDFXMPReader(data: data)
            if !xmp.isValid, document.isEncrypted, let original = PDFEncryptionReader.unencryptedMetadata(url: url) {
                let originalXMP = PDFXMPReader(data: original)
                if originalXMP.isValid { metadataData = original; xmp = originalXMP }
            }
            hasConflictingStandardMetadata = xmp.hasConflictingStandardMetadata
            let fallbacks = ["Title": "http://purl.org/dc/elements/1.1/|title", "Subject": "http://purl.org/dc/elements/1.1/|description", "Author": "http://purl.org/dc/elements/1.1/|creator", "Keywords": "http://ns.adobe.com/pdf/1.3/|Keywords", "Creation application": "http://ns.adobe.com/xap/1.0/|CreatorTool", "PDF producer": "http://ns.adobe.com/pdf/1.3/|Producer", "Created": "http://ns.adobe.com/xap/1.0/|CreateDate", "Modified": "http://ns.adobe.com/xap/1.0/|ModifyDate"]
            if let section = report.sections.firstIndex(where: { $0.id == "document" }) {
                for index in report.sections[section].fields.indices {
                    let field = report.sections[section].fields[index]
                    guard field.value == PDFInspectionFormat.absent,
                          let key = fallbacks.first(where: { String(localized: String.LocalizationValue($0.key)) == field.label })?.value,
                          let values = xmp.propertyValues[key], !values.isEmpty else { continue }
                    report.sections[section].fields[index] = PDFInfoField(field.label, values.joined(separator: "; ") + " (XMP)", id: field.id)
                }
            }
            declarations += xmp.declarations.map { $0 + " (XMP)" }
            if !xmp.isValid { standardMetadataReadable = false; report.notices.append(String(localized: "XMP could not be fully parsed. The original text is available below.")) }
            report.sections.append(PDFInfoSection(id: "xmp-properties", category: .overview, title: String(localized: "XMP properties"), fields: xmp.fields, initiallyExpanded: false))
            report.sections.append(PDFInfoSection(id: "xmp", category: .overview, title: String(localized: "XMP metadata"), fields: [PDFInfoField("XMP", PDFResourceInspector.xmlText(metadataData))], initiallyExpanded: false))
        }
        report.declaredStandards = Array(Set(declarations)).sorted()
        if !standardMetadataReadable { declarations.append(PDFInspectionFormat.unknown + " (XMP)") }
        let standardEmphasis: PDFInfoFieldEmphasis? = if !standardMetadataReadable || hasConflictingStandardMetadata {
            .warning
        } else if !report.declaredStandards.isEmpty {
            .standardDeclaration
        } else {
            nil
        }
        report.sections[0].fields.append(PDFInfoField(
            "Standard according to metadata",
            declarations.isEmpty
                ? String(localized: "No standard specified")
                : Array(Set(declarations)).sorted().joined(separator: "\n"),
            emphasis: standardEmphasis
        ))
        let dates = fileDates ?? (values.creationDate, values.contentModificationDate)
        report.sections.append(PDFInfoSection(id: "filesystem", category: .overview, title: String(localized: "File system dates"), fields: [PDFInfoField("Created", dates.0.map(PDFInspectionFormat.date) ?? PDFInspectionFormat.absent), PDFInfoField("Modified", dates.1.map(PDFInspectionFormat.date) ?? PDFInspectionFormat.absent)], initiallyExpanded: false))
        let extra = PDFObjectReader.fields(document.info, excluding: Set(labels.keys))
        if !extra.isEmpty { report.sections.append(PDFInfoSection(id: "extra-info", category: .overview, title: String(localized: "Additional document properties"), fields: extra, initiallyExpanded: false)) }
        let catalogFields = PDFObjectReader.fields(catalog, excluding: ["Pages", "Metadata", "Outlines", "StructTreeRoot", "Names", "AcroForm", "OutputIntents"])
        report.sections.append(PDFInfoSection(id: "catalog", category: .overview, title: String(localized: "Document catalog"), fields: catalogFields, initiallyExpanded: false))
        let inspector = PDFResourceInspector()
        for (key, value) in PDFObjectReader.pairs(catalog) where !["Pages", "Metadata"].contains(key) {
            inspector.inspect(value, location: "Catalog/" + key)
        }
        let navigation = PDFNavigationReader(document: document)
        if !navigation.bookmarks.isEmpty {
            report.sections.append(PDFInfoSection(id: "outlines", category: .contents, title: String(localized: "Bookmarks"), fields: navigation.bookmarks, initiallyExpanded: false))
        }
        if navigation.incomplete { report.notices.append(String(localized: "Bookmarks or page labels could not be read completely.")) }
        if let structure = PDFObjectReader.object(catalog, "StructTreeRoot") {
            report.sections.append(PDFInfoSection(id: "structure", category: .contents, title: String(localized: "Document structure (not validated)"), fields: [PDFInfoField("Structure", PDFObjectReader.describe(structure))], initiallyExpanded: false))
        }
        progress(report)
        var pageFormats: [String: Set<Int>] = [:]
        for index in 1...max(1, document.numberOfPages) {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { continue }
            let dictionary = page.dictionary
            let userUnit = PDFObjectReader.number(dictionary, "UserUnit") ?? 1
            let crop = page.getBoxRect(.cropBox)
            let rotated = abs(page.rotationAngle) % 180 == 90
            let format = String(format: "%.2f × %.2f mm", (rotated ? crop.height : crop.width) * userUnit * 25.4 / 72, (rotated ? crop.width : crop.height) * userUnit * 25.4 / 72)
            pageFormats[format, default: []].insert(index)
            var fields = [PDFInfoField("Page label", navigation.labels[index] ?? PDFInspectionFormat.unknown), PDFInfoField("Rotation", "\(page.rotationAngle)°"), PDFInfoField("UserUnit", String(userUnit))]
            for (key, box) in [("MediaBox", CGPDFBox.mediaBox), ("CropBox", .cropBox), ("TrimBox", .trimBox), ("BleedBox", .bleedBox), ("ArtBox", .artBox)] {
                let rect = page.getBoxRect(box)
                let dimensions = String(format: "%.2f × %.2f mm", rect.width * userUnit * 25.4 / 72, rect.height * userUnit * 25.4 / 72)
                let origin = String(format: "[%.3f %.3f %.3f %.3f] pt", rect.minX, rect.minY, rect.maxX, rect.maxY)
                // Only MediaBox and CropBox are inheritable page attributes.
                let source = PDFObjectReader.object(dictionary, key) != nil ? String(localized: "Specified") : (["MediaBox", "CropBox"].contains(key) && inherited(dictionary, key) != nil ? String(localized: "Inherited") : String(localized: "Default"))
                fields.append(PDFInfoField(key, "\(dimensions) · \(origin) · \(source)"))
            }
            fields += PDFObjectReader.fields(dictionary, excluding: ["Parent", "Resources", "Contents", "Annots", "MediaBox", "CropBox", "TrimBox", "BleedBox", "ArtBox", "Rotate", "UserUnit"])
            report.sections.append(PDFInfoSection(id: "page-\(index)", category: .pages, title: "\(String(localized: "Page")) \(index)", fields: fields, initiallyExpanded: index == 1))
            let location = "\(String(localized: "Page")) \(index)"
            for (key, value) in PDFObjectReader.pairs(dictionary) where !["Parent", "Resources", "Contents"].contains(key) { inspector.inspect(value, location: location + "/" + key, page: index) }
            let resources = inherited(dictionary, "Resources")
            inspector.inspect(resources, location: location + "/Resources", page: index)
            let scanner = PDFContentScanner(userUnit: userUnit)
            scanner.scan(page: page)
            for annotation in PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(dictionary, "Annots"))) {
                let appearances = PDFObjectReader.dictionary(PDFObjectReader.object(PDFObjectReader.dictionary(annotation), "AP"))
                for (_, appearance) in PDFObjectReader.pairs(appearances) {
                    scanAppearances(appearance, scanner: scanner, resources: PDFObjectReader.dictionary(resources), parent: CGPDFContentStreamCreateWithPage(page))
                }
            }
            inspector.markUsedFonts(scanner.usedFonts, page: index)
            inspector.addScannedImages(scanner, page: index)
            inspector.addScannedColors(scanner, page: index)
            if scanner.incomplete {
                report.notices.append("\(location): " + String(localized: "Content usage could not be fully determined."))
            }
            report.pagesRead = index
            if index % 10 == 0 || index == document.numberOfPages {
                var snapshot = report; snapshot.sections += inspector.results(); progress(snapshot)
            }
        }
        report.sections += inspector.results()
        if !pageFormats.isEmpty {
            let fields = pageFormats.keys.sorted().map { PDFInfoField($0, PDFInspectionFormat.pageList(pageFormats[$0] ?? [])) }
            let firstPage = report.sections.firstIndex(where: { $0.category == .pages }) ?? report.sections.endIndex
            report.sections.insert(PDFInfoSection(id: "page-formats", category: .pages, title: String(localized: "Page formats (CropBox, including rotation)"), fields: fields), at: firstPage)
        }
        if inspector.limited { report.notices.append(String(localized: "Some resources could not be read or reached the analysis limit.")) }
        report.isComplete = !inspector.limited && report.notices.isEmpty
        return report
    }
    private static func security(_ document: CGPDFDocument) -> PDFInfoSection {
        let permissions = document.accessPermissions
        var fields = [PDFInfoField("Encrypted", PDFInspectionFormat.yesNo(document.isEncrypted)), PDFInfoField("Locked", PDFInspectionFormat.yesNo(!document.isUnlocked))]
        for (label, flag) in [("Printing (low quality)", CGPDFAccessPermissions.allowsLowQualityPrinting), ("Printing (high quality)", .allowsHighQualityPrinting), ("Document changes", .allowsDocumentChanges), ("Document assembly", .allowsDocumentAssembly), ("Content copying", .allowsContentCopying), ("Accessibility extraction", .allowsContentAccessibility), ("Commenting", .allowsCommenting), ("Form filling", .allowsFormFieldEntry)] {
            fields.append(PDFInfoField(label, document.isUnlocked ? PDFInspectionFormat.yesNo(permissions.contains(flag)) : PDFInspectionFormat.unknown))
        }
        fields.append(PDFInfoField("Permission source", String(localized: "Core Graphics document permissions")))

        return PDFInfoSection(id: "security", category: .security, title: String(localized: "Security"), fields: fields)
    }
    private static func inherited(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> CGPDFObjectRef? {
        var current = dictionary, seen: Set<UInt> = []
        while let dictionary = current, seen.insert(UInt(bitPattern: dictionary.rawValue)).inserted {
            if let value = PDFObjectReader.object(dictionary, key) { return value }
            current = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "Parent"))
        }
        return nil
    }
    private static func scanAppearances(_ object: CGPDFObjectRef, scanner: PDFContentScanner, resources: CGPDFDictionaryRef?, parent: CGPDFContentStreamRef, depth: Int = 0) {
        guard depth < 16 else { return }
        if let stream = PDFObjectReader.stream(object) { scanner.scan(stream: stream, resources: resources, parent: parent) }
        else { for (_, child) in PDFObjectReader.pairs(PDFObjectReader.dictionary(object)) { scanAppearances(child, scanner: scanner, resources: resources, parent: parent, depth: depth + 1) } }
    }
    private static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return [major, minor]
    }
    private static func effectiveVersion(header: String, catalog: String?) -> String {
        guard let catalog, let override = versionParts(catalog), let original = versionParts(header),
              original.lexicographicallyPrecedes(override) else { return header }
        return catalog
    }
}
