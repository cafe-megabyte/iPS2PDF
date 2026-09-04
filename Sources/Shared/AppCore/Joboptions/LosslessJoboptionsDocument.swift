import Foundation

struct LosslessJoboptionsDocument: Sendable {
    enum StringInsertionStyle: Equatable, Sendable {
        case automatic
        case adobeUnicodeHex
    }

    struct Occurrence: Sendable {
        let path: JoboptionsKeyPath
        let entryByteRange: Range<Int>
        let byteRange: Range<Int>
        let value: JoboptionsValue
        let stringRepresentation: PostScriptStringCodec.Representation?

        var key: String { path.key ?? "" }
    }

    private let source: SourceBuffer
    private let parsed: ParsedSource

    var data: Data { source.data }

    /// Runtime-only programs preserve the encoding of the original source.
    /// This never changes the editable document or its parsed settings.
    func data(appendingPostScript program: String) throws -> Data {
        guard !program.isEmpty else { return data }
        return data + (try source.encode("\n" + program + "\n"))
    }
    var occurrences: [Occurrence] { parsed.occurrences }
    var keys: Set<String> {
        Set(parsed.occurrences.filter { $0.path.components.count == 1 }.map(\.key))
    }
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
        value(forPath: JoboptionsKeyPath(key: key))
    }

    func value(forPath path: JoboptionsKeyPath) -> JoboptionsValue? {
        parsed.occurrences.last { $0.path == path }?.value
    }

    func value(forPath path: String) -> JoboptionsValue? {
        value(forPath: JoboptionsKeyPath(path))
    }

    func replacingValue(forKey key: String, with value: JoboptionsValue) throws -> Self {
        try replacingValue(forPath: JoboptionsKeyPath(key: key), with: value)
    }

    func replacingValue(
        forPath path: JoboptionsKeyPath,
        with value: JoboptionsValue,
        stringInsertionStyle: StringInsertionStyle = .automatic
    ) throws -> Self {
        guard !path.isRoot, let key = path.key else {
            throw JoboptionsError.malformed("empty Joboptions key path")
        }

        var bytes = source.data
        if let occurrence = parsed.occurrences.last(where: { $0.path == path }) {
            let postScript = serialized(
                value,
                preserving: occurrence.stringRepresentation,
                insertionStyle: stringInsertionStyle
            )
            bytes.replaceSubrange(occurrence.byteRange, with: try source.encode(postScript))
        } else {
            guard let closingUnit = parsed.dictionaryClosingUnits[path.parent] else {
                guard !path.parent.isRoot else {
                    throw JoboptionsError.malformed("missing dictionary at \(path.parent.description)")
                }
                return try insertingValueWithMissingDictionaryParents(
                    forPath: path,
                    value: value,
                    stringInsertionStyle: stringInsertionStyle
                )
            }
            let postScript = serialized(
                value,
                preserving: nil,
                insertionStyle: stringInsertionStyle
            )
            let insertion = insertionText(key: key, value: postScript, closingUnit: closingUnit)
            bytes.insert(
                contentsOf: try source.encode(insertion.text),
                at: source.byteOffset(forUnit: insertion.unit)
            )
        }
        return try Self(data: bytes)
    }

    private func insertingValueWithMissingDictionaryParents(
        forPath path: JoboptionsKeyPath,
        value: JoboptionsValue,
        stringInsertionStyle: StringInsertionStyle
    ) throws -> Self {
        let parentComponents = path.parent.components
        var existingParentCount = parentComponents.count
        while existingParentCount > 0 {
            let candidate = JoboptionsKeyPath(Array(parentComponents.prefix(existingParentCount)))
            if parsed.dictionaryClosingUnits[candidate] != nil { break }
            existingParentCount -= 1
        }
        let existingParent = JoboptionsKeyPath(Array(parentComponents.prefix(existingParentCount)))
        guard parsed.dictionaryClosingUnits[existingParent] != nil else {
            throw JoboptionsError.malformed("missing dictionary at \(path.parent.description)")
        }

        var nestedValue = value
        if path.components.count > existingParentCount + 1 {
            for component in path.components[(existingParentCount + 1)...].reversed() {
                nestedValue = .dictionary([component: nestedValue])
            }
        }
        let insertionPath = existingParent.appending(path.components[existingParentCount])
        return try replacingValue(
            forPath: insertionPath,
            with: nestedValue,
            stringInsertionStyle: stringInsertionStyle
        )
    }

    func replacingValue(
        forPath path: String,
        with value: JoboptionsValue,
        stringInsertionStyle: StringInsertionStyle = .automatic
    ) throws -> Self {
        try replacingValue(
            forPath: JoboptionsKeyPath(path),
            with: value,
            stringInsertionStyle: stringInsertionStyle
        )
    }

    func removingValues(forKeys keys: Set<String>) throws -> Self {
        let paths = Set(keys.map { JoboptionsKeyPath(key: $0) })
        return try removingValues(forPaths: paths)
    }

    func removingValues(forPaths paths: Set<JoboptionsKeyPath>) throws -> Self {
        var bytes = source.data
        let ranges = parsed.occurrences
            .filter { paths.contains($0.path) }
            .map(\.entryByteRange)
            .sorted { $0.lowerBound > $1.lowerBound }
        for range in ranges {
            bytes.removeSubrange(range)
        }
        return try Self(data: bytes)
    }

    private func serialized(
        _ value: JoboptionsValue,
        preserving representation: PostScriptStringCodec.Representation?,
        insertionStyle: StringInsertionStyle
    ) -> String {
        guard case let .string(text) = value else { return value.postScript }
        if insertionStyle == .adobeUnicodeHex || representation == .hexadecimal {
            return PostScriptStringCodec.encodeAdobeUnicodeHex(text)
        }
        return PostScriptStringCodec.encodeLiteral(text)
    }

    private func insertionText(
        key: String,
        value: String,
        closingUnit: Int
    ) -> (unit: Int, text: String) {
        var lineStart = closingUnit
        while lineStart > 0 {
            let previous = source.units[lineStart - 1]
            if previous == 0x0A || previous == 0x0D { break }
            lineStart -= 1
        }
        let prefix = source.units[lineStart..<closingUnit]
        let closingIsOnOwnLine = prefix.allSatisfy { $0 == 0x09 || $0 == 0x20 }
        if closingIsOnOwnLine, lineStart < closingUnit || closingUnit > 0 {
            let closingIndent = source.string(forUnits: lineStart..<closingUnit)
            return (
                lineStart,
                "\(closingIndent)  /\(key) \(value)\(source.lineEnding)"
            )
        }
        return (closingUnit, " /\(key) \(value) ")
    }
}
