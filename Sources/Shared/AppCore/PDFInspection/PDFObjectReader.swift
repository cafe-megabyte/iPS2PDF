import CoreGraphics
import Foundation

/// Reads resolved Core Graphics objects. Stream payloads are never expanded by the generic renderer.
enum PDFObjectReader {
    private final class DictionaryEntries {
        var values: [(String, CGPDFObjectRef)] = []
    }
    static func object(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> CGPDFObjectRef? {
        guard let dictionary else { return nil }
        var value: CGPDFObjectRef?
        return CGPDFDictionaryGetObject(dictionary, key, &value) ? value : nil
    }
    static func dictionary(_ object: CGPDFObjectRef?) -> CGPDFDictionaryRef? {
        guard let object else { return nil }
        if CGPDFObjectGetType(object) == .stream { return stream(object).flatMap { CGPDFStreamGetDictionary($0) } }
        var value: CGPDFDictionaryRef?
        return CGPDFObjectGetValue(object, .dictionary, &value) ? value : nil
    }
    static func array(_ object: CGPDFObjectRef?) -> CGPDFArrayRef? {
        guard let object else { return nil }
        var value: CGPDFArrayRef?
        return CGPDFObjectGetValue(object, .array, &value) ? value : nil
    }
    static func stream(_ object: CGPDFObjectRef?) -> CGPDFStreamRef? {
        guard let object else { return nil }
        var value: CGPDFStreamRef?
        return CGPDFObjectGetValue(object, .stream, &value) ? value : nil
    }
    static func elements(_ array: CGPDFArrayRef?) -> [CGPDFObjectRef] {
        guard let array else { return [] }
        return (0..<CGPDFArrayGetCount(array)).compactMap {
            var value: CGPDFObjectRef?
            return CGPDFArrayGetObject(array, $0, &value) ? value : nil
        }
    }
    static func pairs(_ dictionary: CGPDFDictionaryRef?) -> [(String, CGPDFObjectRef)] {
        guard let dictionary else { return [] }
        let result = DictionaryEntries()
        CGPDFDictionaryApplyFunction(dictionary, { key, value, info in
            guard let info else { return }
            Unmanaged<DictionaryEntries>.fromOpaque(info).takeUnretainedValue().values.append((String(cString: key), value))
        }, Unmanaged.passUnretained(result).toOpaque())
        return result.values.sorted { $0.0 < $1.0 }
    }
    static func text(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> String? {
        object(dictionary, key).map { describe($0) }
    }
    static func name(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> String? {
        guard let dictionary else { return nil }
        var pointer: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, key, &pointer), let pointer else { return nil }
        return String(cString: pointer)
    }
    static func number(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> Double? {
        guard let dictionary else { return nil }
        var value: CGPDFReal = 0
        return CGPDFDictionaryGetNumber(dictionary, key, &value) ? Double(value) : nil
    }
    /// Reject non-integral, non-finite and out-of-range PDF numbers before conversion.
    static func integer(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> Int? {
        number(dictionary, key).flatMap { Int(exactly: $0) }
    }
    static func boolean(_ dictionary: CGPDFDictionaryRef?, _ key: String) -> Bool? {
        guard let dictionary else { return nil }
        var value: CGPDFBoolean = 0
        return CGPDFDictionaryGetBoolean(dictionary, key, &value) ? value != 0 : nil
    }
    static func data(_ stream: CGPDFStreamRef) -> Data? {
        streamData(stream)?.data
    }
    static func streamData(_ stream: CGPDFStreamRef) -> (data: Data, format: CGPDFDataFormat)? {
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }
        return (data, format)
    }
    static func describe(_ object: CGPDFObjectRef, depth: Int = 0, ancestors: Set<UInt> = [], redacting: Set<String> = []) -> String {
        switch CGPDFObjectGetType(object) {
        case .null: return "null"
        case .boolean:
            var value: CGPDFBoolean = 0
            CGPDFObjectGetValue(object, .boolean, &value)
            return PDFInspectionFormat.yesNo(value != 0)
        case .integer:
            var value: CGPDFInteger = 0
            CGPDFObjectGetValue(object, .integer, &value)
            return String(value)
        case .real:
            var value: CGPDFReal = 0
            CGPDFObjectGetValue(object, .real, &value)
            return String(format: "%.5g", Double(value))
        case .name:
            var value: UnsafePointer<CChar>?
            CGPDFObjectGetValue(object, .name, &value)
            return value.map { String(cString: $0) } ?? PDFInspectionFormat.unknown
        case .string:
            var value: CGPDFStringRef?
            CGPDFObjectGetValue(object, .string, &value)
            guard let value else { return PDFInspectionFormat.unknown }
            return (CGPDFStringCopyTextString(value) as String?) ?? PDFInspectionFormat.unknown
        case .stream:
            return String(localized: "Stream") + " " + describeDictionary(dictionary(object), depth: depth, ancestors: ancestors, redacting: redacting)
        case .dictionary:
            return describeDictionary(dictionary(object), depth: depth, ancestors: ancestors, redacting: redacting)
        case .array:
            guard depth < 8 else { return String(localized: "Nested data (depth limit)") }
            return "[" + elements(array(object)).map { describe($0, depth: depth + 1, ancestors: ancestors, redacting: redacting) }.joined(separator: ", ") + "]"
        @unknown default: return PDFInspectionFormat.unknown
        }
    }
    static func describeDictionary(_ dictionary: CGPDFDictionaryRef?, depth: Int, ancestors: Set<UInt>, redacting: Set<String> = []) -> String {
        guard let dictionary else { return PDFInspectionFormat.unknown }
        let identity = UInt(bitPattern: dictionary.rawValue)
        guard depth < 8, !ancestors.contains(identity) else { return String(localized: "Nested reference") }
        var ancestors = ancestors; ancestors.insert(identity)
        // Parent and page-tree references point back to whole documents rather than metadata values.
        return "{ " + pairs(dictionary).filter { !redacting.contains($0.0) }.map { key, value in
            let rendered = ["Parent", "P", "Pages", "StructTreeRoot"].contains(key) && [.dictionary, .array].contains(CGPDFObjectGetType(value))
                ? String(localized: "Reference") : describe(value, depth: depth + 1, ancestors: ancestors, redacting: redacting)
            return "/\(key): \(rendered)"
        }.joined(separator: "; ") + " }"
    }
    static func fields(_ dictionary: CGPDFDictionaryRef?, excluding: Set<String> = [], redacting: Set<String> = []) -> [PDFInfoField] {
        pairs(dictionary).filter { !excluding.union(redacting).contains($0.0) }.map { PDFInfoField($0.0, describe($0.1, redacting: redacting)) }
    }
}
