import CoreGraphics
import Foundation

/// Reads navigation from the independently unlocked Core Graphics document. PDFKit
/// may remain locked for a valid Unicode password; it is not an authoritative fallback.
final class PDFNavigationReader {
    private(set) var labels: [Int: String] = [:]
    private(set) var bookmarks: [PDFInfoField] = []
    private(set) var incomplete = false
    private var labelRanges: [Int: CGPDFDictionaryRef] = [:]
    private var pageNumbers: [UInt: Int] = [:]
    private var visited: Set<UInt> = []
    private var nodes = 0

    init(document: CGPDFDocument) {
        if let object = PDFObjectReader.object(document.catalog, "PageLabels") {
            readLabels(object, depth: 0)
            if labelRanges.isEmpty { incomplete = true }
        }
        let starts = labelRanges.keys.sorted()
        var rangeIndex = 0
        for index in 1...max(1, document.numberOfPages) {
            guard let page = document.page(at: index), let dictionary = page.dictionary else { incomplete = true; continue }
            pageNumbers[UInt(bitPattern: dictionary.rawValue)] = index
            if !starts.isEmpty {
                while rangeIndex + 1 < starts.count, starts[rangeIndex + 1] < index { rangeIndex += 1 }
                let start = starts[rangeIndex]
                if start < index, let range = labelRanges[start] { labels[index] = label(range, offset: index - 1 - start) }
                else { labels[index] = PDFInspectionFormat.unknown; incomplete = true }
            } else {
                labels[index] = incomplete ? PDFInspectionFormat.unknown : String(index)
            }
        }
        visited.removeAll(); nodes = 0
        let outlines = PDFObjectReader.dictionary(PDFObjectReader.object(document.catalog, "Outlines"))
        if let first = PDFObjectReader.object(outlines, "First") { readBookmarks(first, depth: 0) }
    }
    private func enter(_ dictionary: CGPDFDictionaryRef, depth: Int) -> Bool {
        nodes += 1
        guard depth < 64, nodes <= 100_000, !Task.isCancelled,
              visited.insert(UInt(bitPattern: dictionary.rawValue)).inserted else { incomplete = true; return false }
        return true
    }
    private func readLabels(_ object: CGPDFObjectRef, depth: Int) {
        guard let dictionary = PDFObjectReader.dictionary(object), enter(dictionary, depth: depth) else { incomplete = true; return }
        let values = PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(dictionary, "Nums")))
        if !values.count.isMultiple(of: 2) { incomplete = true }
        for index in stride(from: 0, to: values.count - values.count % 2, by: 2) {
            guard CGPDFObjectGetType(values[index]) == .integer, let start = Int(PDFObjectReader.describe(values[index])), start >= 0,
                  let range = PDFObjectReader.dictionary(values[index + 1]) else { incomplete = true; continue }
            if labelRanges[start] != nil { incomplete = true }
            labelRanges[start] = range
        }
        for child in PDFObjectReader.elements(PDFObjectReader.array(PDFObjectReader.object(dictionary, "Kids"))) { readLabels(child, depth: depth + 1) }
    }
    private func label(_ dictionary: CGPDFDictionaryRef, offset: Int) -> String {
        let prefix = PDFObjectReader.text(dictionary, "P") ?? ""
        guard let styleObject = PDFObjectReader.object(dictionary, "S") else { return prefix }
        let style = PDFObjectReader.describe(styleObject)
        let start = PDFObjectReader.object(dictionary, "St") == nil ? 1 : PDFObjectReader.integer(dictionary, "St")
        guard let start, start > 0 else { incomplete = true; return PDFInspectionFormat.unknown }
        let (number, overflow) = start.addingReportingOverflow(offset)
        guard !overflow else { incomplete = true; return PDFInspectionFormat.unknown }
        switch style {
        case "D": return prefix + String(number)
        case "r", "R":
            // Bound expansion of malformed numeric values (e.g. trillions of M's).
            guard number <= 1_000_000 else { incomplete = true; return PDFInspectionFormat.unknown }
            var remaining = number, roman = ""
            for (value, symbol) in [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")] {
                while remaining >= value { roman += symbol; remaining -= value }
            }
            return prefix + (style == "r" ? roman.lowercased() : roman)
        case "a", "A":
            let repeats = (number - 1) / 26 + 1
            guard repeats <= 4096 else { incomplete = true; return PDFInspectionFormat.unknown }
            let character = String(UnicodeScalar((style == "a" ? 97 : 65) + (number - 1) % 26)!)
            return prefix + String(repeating: character, count: repeats)
        default: incomplete = true; return PDFInspectionFormat.unknown
        }
    }
    private func readBookmarks(_ first: CGPDFObjectRef, depth: Int) {
        var current: CGPDFObjectRef? = first
        while let object = current {
            guard let dictionary = PDFObjectReader.dictionary(object), enter(dictionary, depth: depth) else { incomplete = true; return }
            let title = PDFObjectReader.text(dictionary, "Title") ?? PDFInspectionFormat.unknown
            let action = PDFObjectReader.dictionary(PDFObjectReader.object(dictionary, "A"))
            let destination = PDFObjectReader.object(dictionary, "Dest") ?? PDFObjectReader.object(action, "D")
            var target = destination.map { PDFObjectReader.describe($0) } ?? ""
            if let first = PDFObjectReader.elements(PDFObjectReader.array(destination)).first,
               let page = PDFObjectReader.dictionary(first), let index = pageNumbers[UInt(bitPattern: page.rawValue)] {
                target = labels[index] ?? String(index)
            }
            bookmarks.append(PDFInfoField(String(repeating: "  ", count: depth) + title, target, id: "outline-\(bookmarks.count)"))
            if let child = PDFObjectReader.object(dictionary, "First") { readBookmarks(child, depth: depth + 1) }
            current = PDFObjectReader.object(dictionary, "Next")
        }
    }
}
