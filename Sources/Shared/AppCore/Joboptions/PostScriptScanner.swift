import Foundation

struct PostScriptScanner {
    private let source: SourceBuffer
    private var index = 0
    private var result = ParsedSource()
    private var currentOccurrences: [LosslessJoboptionsDocument.Occurrence] = []
    private var currentDictionaryClosingUnits: [JoboptionsKeyPath: Int] = [:]
    private var lastTopLevelOccurrences: [LosslessJoboptionsDocument.Occurrence] = []
    private var lastTopLevelDictionaryClosingUnits: [JoboptionsKeyPath: Int] = [:]
    private var lastTopLevelDictionaryClosingUnit: Int?

    init(source: SourceBuffer) {
        self.source = source
    }

    mutating func scan() throws -> ParsedSource {
        while true {
            skipTrivia()
            guard index < source.units.count else { break }

            if source.units[index] == 0x3C, peek(1) == 0x3C {
                currentOccurrences = []
                currentDictionaryClosingUnits = [:]
                let object = try parseObject(recordDictionaryEntries: true, path: JoboptionsKeyPath([]))
                lastTopLevelDictionaryClosingUnit = object.dictionaryClosingUnit
                lastTopLevelOccurrences = currentOccurrences
                lastTopLevelDictionaryClosingUnits = currentDictionaryClosingUnits
                continue
            }

            let object = try parseObject(recordDictionaryEntries: false, path: JoboptionsKeyPath([]))
            if case let .raw(token) = object.value,
               token == "setdistillerparams",
               let closingUnit = lastTopLevelDictionaryClosingUnit,
               result.primaryDictionaryClosingUnit == nil {
                result.primaryDictionaryClosingUnit = closingUnit
                result.occurrences = lastTopLevelOccurrences
                result.dictionaryClosingUnits = lastTopLevelDictionaryClosingUnits
            } else if case let .raw(token) = object.value,
                      token != "setpagedevice" {
                result.unclassifiedFragments.append(object.unitRange)
            }
        }
        return result
    }

    private mutating func parseObject(
        recordDictionaryEntries: Bool,
        path: JoboptionsKeyPath
    ) throws -> ParsedObject {
        skipTrivia()
        guard index < source.units.count else {
            throw JoboptionsError.malformed("unexpected end of file")
        }

        let start = index
        switch source.units[index] {
        case 0x28:
            return try parseLiteralString(start: start)
        case 0x3C where peek(1) == 0x3C:
            return try parseDictionary(start: start, recordEntries: recordDictionaryEntries, path: path)
        case 0x3C:
            return try parseHexString(start: start)
        case 0x5B:
            return try parseArray(start: start)
        case 0x7B:
            return try parseProcedure(start: start)
        case 0x2F:
            index += 1
            let nameStart = index
            consumeToken()
            let name = source.string(forUnits: nameStart..<index)
            return ParsedObject(value: .name(name), unitRange: start..<index, dictionaryClosingUnit: nil)
        case 0x5D, 0x7D, 0x3E:
            throw JoboptionsError.malformed("unexpected closing delimiter")
        default:
            consumeToken()
            guard index > start else {
                throw JoboptionsError.malformed("unsupported delimiter")
            }
            let token = source.string(forUnits: start..<index)
            let value: JoboptionsValue
            if token == "true" {
                value = .boolean(true)
            } else if token == "false" {
                value = .boolean(false)
            } else if let number = Double(token) {
                value = .number(number, original: token)
            } else {
                value = .raw(token)
            }
            return ParsedObject(value: value, unitRange: start..<index, dictionaryClosingUnit: nil)
        }
    }

    private mutating func parseDictionary(
        start: Int,
        recordEntries: Bool,
        path: JoboptionsKeyPath
    ) throws -> ParsedObject {
        index += 2
        var values: [String: JoboptionsValue] = [:]

        while true {
            skipTrivia()
            guard index < source.units.count else {
                throw JoboptionsError.malformed("unterminated dictionary")
            }
            if source.units[index] == 0x3E, peek(1) == 0x3E {
                let closingUnit = index
                index += 2
                if recordEntries { currentDictionaryClosingUnits[path] = closingUnit }
                return ParsedObject(
                    value: .dictionary(values),
                    unitRange: start..<index,
                    dictionaryClosingUnit: closingUnit
                )
            }

            if source.units[index] == 0x2F {
                let entryStart = index
                index += 1
                let keyStart = index
                consumeToken()
                guard index > keyStart else {
                    throw JoboptionsError.malformed("empty dictionary key")
                }
                let key = source.string(forUnits: keyStart..<index)
                let entryPath = path.appending(key)
                skipTrivia()
                let value = try parseObject(
                    recordDictionaryEntries: recordEntries,
                    path: entryPath
                )
                values[key] = value.value
                if recordEntries {
                    currentOccurrences.append(
                        .init(
                            path: entryPath,
                            entryByteRange: source.byteRange(forUnits: entryStart..<value.unitRange.upperBound),
                            byteRange: source.byteRange(forUnits: value.unitRange),
                            value: value.value,
                            stringRepresentation: value.stringRepresentation
                        )
                    )
                }
            } else {
                let fragment = try parseObject(recordDictionaryEntries: false, path: path)
                result.unclassifiedFragments.append(fragment.unitRange)
            }
        }
    }

    private mutating func parseArray(start: Int) throws -> ParsedObject {
        index += 1
        var values: [JoboptionsValue] = []
        while true {
            skipTrivia()
            guard index < source.units.count else {
                throw JoboptionsError.malformed("unterminated array")
            }
            if source.units[index] == 0x5D {
                index += 1
                return ParsedObject(value: .array(values), unitRange: start..<index, dictionaryClosingUnit: nil)
            }
            values.append(
                try parseObject(recordDictionaryEntries: false, path: JoboptionsKeyPath([])).value
            )
        }
    }

    private mutating func parseLiteralString(start: Int) throws -> ParsedObject {
        index += 1
        var depth = 1
        while index < source.units.count {
            let unit = source.units[index]
            index += 1
            if unit == 0x5C {
                if index < source.units.count { index += 1 }
            } else if unit == 0x28 {
                depth += 1
            } else if unit == 0x29 {
                depth -= 1
                if depth == 0 {
                    let raw = source.string(forUnits: (start + 1)..<(index - 1))
                    return ParsedObject(
                        value: .string(PostScriptStringCodec.decodeLiteral(raw)),
                        unitRange: start..<index,
                        dictionaryClosingUnit: nil,
                        stringRepresentation: .literal
                    )
                }
            }
        }
        throw JoboptionsError.malformed("unterminated string")
    }

    private mutating func parseHexString(start: Int) throws -> ParsedObject {
        index += 1
        let contentStart = index
        while index < source.units.count, source.units[index] != 0x3E {
            index += 1
        }
        guard index < source.units.count else {
            throw JoboptionsError.malformed("unterminated hexadecimal string")
        }
        let content = source.string(forUnits: contentStart..<index)
        index += 1
        let raw = source.string(forUnits: start..<index)
        return ParsedObject(
            value: PostScriptStringCodec.decodeHexadecimal(content).map(JoboptionsValue.string) ?? .raw(raw),
            unitRange: start..<index,
            dictionaryClosingUnit: nil,
            stringRepresentation: .hexadecimal
        )
    }

    private mutating func parseProcedure(start: Int) throws -> ParsedObject {
        index += 1
        var depth = 1
        while index < source.units.count {
            if source.units[index] == 0x25 {
                skipComment()
            } else if source.units[index] == 0x28 {
                _ = try parseLiteralString(start: index)
            } else if source.units[index] == 0x7B {
                depth += 1
                index += 1
            } else if source.units[index] == 0x7D {
                depth -= 1
                index += 1
                if depth == 0 {
                    return ParsedObject(
                        value: .raw(source.string(forUnits: start..<index)),
                        unitRange: start..<index,
                        dictionaryClosingUnit: nil
                    )
                }
            } else {
                index += 1
            }
        }
        throw JoboptionsError.malformed("unterminated procedure")
    }

    private mutating func skipTrivia() {
        while index < source.units.count {
            if isWhitespace(source.units[index]) {
                index += 1
            } else if source.units[index] == 0x25 {
                skipComment()
            } else {
                return
            }
        }
    }

    private mutating func skipComment() {
        while index < source.units.count {
            let unit = source.units[index]
            index += 1
            if unit == 0x0A || unit == 0x0D { return }
        }
    }

    private mutating func consumeToken() {
        while index < source.units.count, !isDelimiter(source.units[index]) {
            index += 1
        }
    }

    private func peek(_ offset: Int) -> UInt32? {
        let target = index + offset
        return source.units.indices.contains(target) ? source.units[target] : nil
    }

    private func isWhitespace(_ unit: UInt32) -> Bool {
        unit == 0 || unit == 9 || unit == 10 || unit == 12 || unit == 13 || unit == 32
    }

    private func isDelimiter(_ unit: UInt32) -> Bool {
        isWhitespace(unit) || [0x28, 0x29, 0x3C, 0x3E, 0x5B, 0x5D, 0x7B, 0x7D, 0x2F, 0x25].contains(unit)
    }
}
