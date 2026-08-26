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
