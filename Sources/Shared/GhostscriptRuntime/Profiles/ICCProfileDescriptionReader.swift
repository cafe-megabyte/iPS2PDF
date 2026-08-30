import Foundation

enum ICCProfileDescriptionReader {
    static func descriptions(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 132,
              let declaredSize = unsignedInteger(in: data, at: 0),
              declaredSize >= 132,
              declaredSize <= data.count,
              String(data: data[36..<40], encoding: .ascii) == "acsp",
              let tagCount = unsignedInteger(in: data, at: 128),
              tagCount <= 4_096,
              132 + tagCount * 12 <= declaredSize
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var results: [String] = []
        for index in 0..<tagCount {
            let recordOffset = 132 + index * 12
            guard String(data: data[recordOffset..<(recordOffset + 4)], encoding: .ascii) == "desc",
                  let tagOffset = unsignedInteger(in: data, at: recordOffset + 4),
                  let tagSize = unsignedInteger(in: data, at: recordOffset + 8),
                  tagSize >= 12,
                  tagOffset <= declaredSize,
                  tagSize <= declaredSize - tagOffset
            else { continue }

            results.append(contentsOf: descriptions(
                in: data,
                tagOffset: tagOffset,
                tagSize: tagSize
            ))
        }
        return Array(Set(results)).sorted()
    }

    static func outputConditionIdentifier(at url: URL) throws -> String? {
        let data = try validatedData(at: url)
        guard let target = textTag("targ", in: data) else { return nil }
        let normalized = target.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        )
        if normalized.hasPrefix("ICCHDAT ") {
            let value = String(normalized.dropFirst("ICCHDAT ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        let pattern = #"(?:FILE_)?DESCRIPTOR\s+[\"']([^\"']+)[\"']"#
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        guard let match = expression.firstMatch(in: normalized, range: range),
              let descriptorRange = Range(match.range(at: 1), in: normalized)
        else { return nil }
        return outputConditionIdentifier(forCharacterizationDescriptor: String(
            normalized[descriptorRange]
        ))
    }

    private static func validatedData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count >= 132,
              let declaredSize = unsignedInteger(in: data, at: 0),
              declaredSize >= 132,
              declaredSize <= data.count,
              String(data: data[36..<40], encoding: .ascii) == "acsp",
              let tagCount = unsignedInteger(in: data, at: 128),
              tagCount <= 4_096,
              132 + tagCount * 12 <= declaredSize
        else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }

    private static func textTag(_ signature: String, in data: Data) -> String? {
        guard let declaredSize = unsignedInteger(in: data, at: 0),
              let tagCount = unsignedInteger(in: data, at: 128)
        else { return nil }
        for index in 0..<tagCount {
            let recordOffset = 132 + index * 12
            guard String(data: data[recordOffset..<(recordOffset + 4)], encoding: .ascii)
                    == signature,
                  let tagOffset = unsignedInteger(in: data, at: recordOffset + 4),
                  let tagSize = unsignedInteger(in: data, at: recordOffset + 8),
                  tagSize >= 8,
                  tagOffset <= declaredSize,
                  tagSize <= declaredSize - tagOffset,
                  String(data: data[tagOffset..<(tagOffset + 4)], encoding: .ascii) == "text"
            else { continue }
            return String(
                data: data[(tagOffset + 8)..<(tagOffset + tagSize)],
                encoding: .isoLatin1
            )
        }
        return nil
    }

    private static func outputConditionIdentifier(
        forCharacterizationDescriptor descriptor: String
    ) -> String? {
        let value = descriptor.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value == "FOGRA39L_CG" { return "FOGRA50" }
        if value == "FOGRA39L_CM" { return "FOGRA49" }
        guard value.hasPrefix("FOGRA") else { return nil }
        let suffix = value.dropFirst("FOGRA".count)
        let digits = suffix.prefix(while: \Character.isNumber)
        guard !digits.isEmpty else { return nil }
        let remainder = suffix.dropFirst(digits.count)
        guard remainder.isEmpty || remainder == "L" else { return nil }
        return "FOGRA\(digits)"
    }

    private static func descriptions(
        in data: Data,
        tagOffset: Int,
        tagSize: Int
    ) -> [String] {
        guard tagOffset + 12 <= data.count,
              let type = String(data: data[tagOffset..<(tagOffset + 4)], encoding: .ascii)
        else { return [] }

        switch type {
        case "desc":
            guard let count = unsignedInteger(in: data, at: tagOffset + 8),
                  count > 0,
                  count <= tagSize - 12
            else { return [] }
            let bytes = data[(tagOffset + 12)..<(tagOffset + 12 + count)]
            guard let value = String(data: bytes, encoding: .ascii) else { return [] }
            return normalizedValues([value])

        case "mluc":
            guard tagSize >= 16,
                  let count = unsignedInteger(in: data, at: tagOffset + 8),
                  let recordSize = unsignedInteger(in: data, at: tagOffset + 12),
                  count <= 4_096,
                  recordSize >= 12,
                  count * recordSize <= tagSize - 16
            else { return [] }

            var values: [String] = []
            for index in 0..<count {
                let recordOffset = tagOffset + 16 + index * recordSize
                guard let length = unsignedInteger(in: data, at: recordOffset + 4),
                      let relativeOffset = unsignedInteger(in: data, at: recordOffset + 8),
                      length.isMultiple(of: 2),
                      relativeOffset <= tagSize,
                      length <= tagSize - relativeOffset
                else { continue }
                let start = tagOffset + relativeOffset
                let bytes = data[start..<(start + length)]
                if let value = String(data: bytes, encoding: .utf16BigEndian) {
                    values.append(value)
                }
            }
            return normalizedValues(values)

        default:
            return []
        }
    }

    private static func unsignedInteger(in data: Data, at offset: Int) -> Int? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func normalizedValues(_ values: [String]) -> [String] {
        values.compactMap { value in
            let normalized = value
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            return normalized.isEmpty ? nil : normalized
        }
    }
}
