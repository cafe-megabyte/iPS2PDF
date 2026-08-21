import Foundation

struct LosslessJoboptionsDocument: Sendable {
    struct Occurrence: Sendable {
        let key: String
        let entryByteRange: Range<Int>
        let byteRange: Range<Int>
        let value: JoboptionsValue
    }

    private let source: SourceBuffer
    private let parsed: ParsedSource

    var data: Data { source.data }
    var occurrences: [Occurrence] { parsed.occurrences }
    var keys: Set<String> { Set(parsed.occurrences.map(\.key)) }
    var hasUnclassifiedFragments: Bool { !parsed.unclassifiedFragments.isEmpty }

    var sourceText: String {
        source.decodedString ?? "<Binary Joboptions>"
    }

    init(data: Data) throws {
        guard !data.isEmpty else { throw JoboptionsError.empty }
        guard data.count <= 16 * 1_024 * 1_024 else { throw JoboptionsError.tooLarge }
        let source = try SourceBuffer(data: data)
        var scanner = PostScriptScanner(source: source)
        let parsed = try scanner.scan()
        guard parsed.primaryDictionaryClosingUnit != nil else {
            throw JoboptionsError.missingDistillerDictionary
        }
        self.source = source
        self.parsed = parsed
    }

    func value(forKey key: String) -> JoboptionsValue? {
        parsed.occurrences.last { $0.key == key }?.value
    }

    func replacingValue(forKey key: String, with value: JoboptionsValue) throws -> Self {
        var bytes = source.data
        let replacement = try source.encode(value.postScript)

        if let occurrence = parsed.occurrences.last(where: { $0.key == key }) {
            bytes.replaceSubrange(occurrence.byteRange, with: replacement)
        } else {
            guard let closingUnit = parsed.primaryDictionaryClosingUnit else {
                throw JoboptionsError.missingDistillerDictionary
            }
            let insertion = source.lineEnding + "  /\(key) \(value.postScript)"
            let insertionData = try source.encode(insertion)
            let byteOffset = source.byteOffset(forUnit: closingUnit)
            bytes.insert(contentsOf: insertionData, at: byteOffset)
        }
        return try Self(data: bytes)
    }

    func removingValues(forKeys keys: Set<String>) throws -> Self {
        var bytes = source.data
        let ranges = parsed.occurrences
            .filter { keys.contains($0.key) }
            .map(\.entryByteRange)
            .sorted { $0.lowerBound > $1.lowerBound }
        for range in ranges {
            bytes.removeSubrange(range)
        }
        return try Self(data: bytes)
    }
}
