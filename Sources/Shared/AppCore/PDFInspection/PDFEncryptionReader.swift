import CoreGraphics
import Foundation

/// Core Graphics exposes permissions but no trailer accessor. An isolated, temporary
/// incremental catalog makes the original encryption dictionary reachable through its
/// existing cross-reference entries. Original objects and encryption are preserved;
/// only name/number dictionaries are appended. No document contents are converted.
enum PDFEncryptionReader {
    struct Details {
        let fields: [PDFInfoField]
        let isComplete: Bool
        let allowsContentCopying: Bool?
    }
    private static let secretKeys: Set<String> = ["O", "U", "OE", "UE", "Perms", "Recipients"]

    static func inspect(url: URL, password: String?) -> Details? {
        read(url: url, password: password, encrypted: true) { document in
            guard let dictionary = PDFObjectReader.dictionary(PDFObjectReader.object(document.catalog, "InspectionEncryption")) else { return nil }
            var complete = true
            var allowsContentCopying: Bool?
            var fields = PDFObjectReader.fields(dictionary, excluding: ["CF"], redacting: secretKeys)
            let handler = PDFObjectReader.name(dictionary, "Filter") ?? PDFInspectionFormat.unknown
            let version = PDFObjectReader.number(dictionary, "V") ?? 0
            let revision = PDFObjectReader.number(dictionary, "R") ?? 0
            fields.insert(PDFInfoField("Security handler", handler), at: 0)
            if handler == "Standard", version == 1 || version == 2 {
                let length = PDFObjectReader.object(dictionary, "Length") == nil ? 40 : PDFObjectReader.integer(dictionary, "Length")
                if let length, (40...128).contains(length), length.isMultiple(of: 8) {
                    fields.insert(PDFInfoField("Encryption algorithm / key length", "RC4 · \(length) bit"), at: 1)
                } else {
                    complete = false
                    fields.insert(PDFInfoField("Encryption algorithm / key length", PDFInspectionFormat.unknown), at: 1)
                }
            }
            let filters = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "CF"))
            for (key, value) in PDFObjectReader.pairs(filters) {
                let filter = PDFObjectReader.dictionary(value)
                let method = PDFObjectReader.name(filter, "CFM") ?? "None"
                let algorithm = method == "AESV2" ? "AES-128" : method == "AESV3" ? "AES-256" : method == "V2" ? "RC4" : method
                fields.append(PDFInfoField("Encryption algorithm / key length", algorithm + " (" + key + ")"))
                fields.append(PDFInfoField(String(localized: "Crypt filter") + " " + key, PDFObjectReader.describeDictionary(filter, depth: 0, ancestors: [], redacting: secretKeys)))
            }
            if handler == "Standard", let permissions = PDFObjectReader.integer(dictionary, "P"), permissions >= Int(Int32.min), permissions <= Int(UInt32.max) {
                let bits = UInt32(truncatingIfNeeded: Int64(permissions))
                let definitions: [(String, Int)] = [("Printing (low quality)", 3), ("Document changes", 4), ("Content copying", 5), ("Commenting", 6), ("Form filling", 9), ("Accessibility extraction", 10), ("Document assembly", 11), ("Printing (high quality)", 12)]
                for (label, bit) in definitions {
                    let effectiveBit = revision < 3 && bit >= 9 ? (bit == 9 ? 6 : bit == 10 ? 5 : bit == 11 ? 4 : 3) : bit
                    var permitted = bits & (1 << (effectiveBit - 1)) != 0
                    // PDF Reference 1.7, table 3.20: high-quality printing also
                    // requires printing; commenting includes filling existing fields.
                    if revision >= 3, bit == 12 { permitted = permitted && bits & (1 << 2) != 0 }
                    if revision >= 3, bit == 9 { permitted = permitted || bits & (1 << 5) != 0 }
                    if bit == 5 { allowsContentCopying = permitted }
                    fields.append(PDFInfoField(String(localized: "Declared permission") + " · " + String(localized: String.LocalizationValue(label)), PDFInspectionFormat.yesNo(permitted)))
                }
            }
            fields.append(PDFInfoField("Metadata encrypted", PDFInspectionFormat.yesNo(PDFObjectReader.boolean(dictionary, "EncryptMetadata") ?? true)))
            if handler == "Standard", PDFObjectReader.integer(dictionary, "P") == nil { complete = false }
            return Details(
                fields: fields.enumerated().map { PDFInfoField($0.element.label, $0.element.value, id: "encryption-\($0.offset)") },
                isComplete: complete,
                allowsContentCopying: allowsContentCopying
            )
        }
    }

    /// Some producers leave XMP in clear text even for older encryption revisions
    /// whose reader decrypts every stream. Try the original bytes only after normal
    /// metadata decoding fails; callers accept this fallback only if it parses as XML.
    static func unencryptedMetadata(url: URL) -> Data? {
        read(url: url, password: nil, encrypted: false) { document in
            let root = PDFObjectReader.dictionary(PDFObjectReader.object(document.catalog, "InspectionOriginalRoot"))
            return PDFObjectReader.stream(PDFObjectReader.object(root, "Metadata")).flatMap(PDFObjectReader.data)
        }
    }

    private static func read<Result>(url: URL, password: String?, encrypted: Bool, body: (CGPDFDocument) -> Result?) -> Result? {
        do {
            let source = try FileHandle(forReadingFrom: url)
            defer { try? source.close() }
            let size = try source.seekToEnd()
            try source.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
            let tail = String(decoding: try source.readToEnd() ?? Data(), as: UTF8.self)
            guard let range = tail.range(of: "startxref", options: .backwards),
                  let offset = UInt64(tail[range.upperBound...].split(whereSeparator: \.isWhitespace).first ?? "") else { return nil }
            var cursor = offset, seen: Set<UInt64> = [], trailer: [String: String] = [:]
            while cursor < size, seen.count < 128, seen.insert(cursor).inserted {
                try Task.checkCancellation()
                try source.seek(toOffset: cursor)
                let data = try source.read(upToCount: 16 * 1024 * 1024) ?? Data()
                var reader = TrailerLexer(data: data)
                let first = try reader.token()
                if first == "xref" {
                    while try reader.token() != "trailer" { }
                } else {
                    guard Int(first) != nil, Int(try reader.token()) != nil, try reader.token() == "obj" else { return nil }
                }
                let properties = try reader.dictionary()
                for (key, value) in properties where trailer[key] == nil { trailer[key] = value }
                guard let previous = properties["Prev"].flatMap(UInt64.init) else { break }
                cursor = previous
            }
            guard let encryption = trailer["Encrypt"], encryption != "null",
                  let count = trailer["Size"].flatMap(Int.init), count > 0, count < Int.max - 3 else { return nil }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PDFSecurity-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: folder) }
            let copy = folder.appendingPathComponent("Inspection.pdf")
            try FileManager.default.copyItem(at: url, to: copy)
            let output = try FileHandle(forWritingTo: copy)
            defer { try? output.close() }
            try output.seekToEnd()
            var addition = "\n"
            var offsets: [UInt64] = []
            for (index, body) in [
                "<< /Type /Catalog /Pages \(count + 1) 0 R /InspectionEncryption \(encryption) /InspectionOriginalRoot \(trailer["Root"] ?? "null") >>",
                "<< /Type /Pages /Kids [\(count + 2) 0 R] /Count 1 >>",
                "<< /Type /Page /Parent \(count + 1) 0 R /MediaBox [0 0 1 1] >>"
            ].enumerated() {
                offsets.append(size + UInt64(addition.utf8.count))
                addition += "\(count + index) 0 obj\n\(body)\nendobj\n"
            }
            let xref = size + UInt64(addition.utf8.count)
            addition += "xref\n\(count) 3\n"
            for offset in offsets { addition += String(format: "%010llu 00000 n \n", offset) }
            addition += "trailer\n<< /Size \(count + 3) /Root \(count) 0 R /Prev \(offset) /Encrypt \(encrypted ? encryption : "null")"
            if let id = trailer["ID"] { addition += " /ID " + id }
            addition += " >>\nstartxref\n\(xref)\n%%EOF\n"
            try output.write(contentsOf: Data(addition.utf8))
            try output.synchronize()
            guard let document = CGPDFDocument(copy as CFURL) else { return nil }
            if !document.isUnlocked { _ = document.unlockWithPassword(password ?? "") }
            guard document.isUnlocked else { return nil }
            return body(document)
        } catch { return nil }
    }
}
