import Foundation

enum PDFInspectionFormat {
    static let unknown = String(localized: "Not determinable")
    static let absent = String(localized: "Not specified")
    static func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }
    static func pageList(_ pages: Set<Int>) -> String {
        let sorted = pages.sorted()
        guard let first = sorted.first else { return absent }
        var start = first, end = first
        var ranges: [String] = []
        for page in sorted.dropFirst() {
            if page == end + 1 { end = page; continue }
            ranges.append(start == end ? "\(start)" : "\(start)–\(end)")
            start = page; end = page
        }
        ranges.append(start == end ? "\(start)" : "\(start)–\(end)")
        return ranges.joined(separator: ", ")
    }
}
