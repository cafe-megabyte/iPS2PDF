import Foundation

struct SourceBuffer: Sendable {
    enum Encoding: Sendable {
        case utf8(bomLength: Int)
        case isoLatin1
        case utf16LittleEndian
        case utf16BigEndian
    }

    let data: Data
    let units: [UInt32]
    let encoding: Encoding

    init(data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xFF, 0xFE]) {
            guard bytes.count.isMultiple(of: 2) else {
                throw JoboptionsError.unsupportedEncoding
            }
            encoding = .utf16LittleEndian
            units = stride(from: 2, to: bytes.count, by: 2).map {
                UInt32(bytes[$0]) | UInt32(bytes[$0 + 1]) << 8
            }
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            guard bytes.count.isMultiple(of: 2) else {
                throw JoboptionsError.unsupportedEncoding
            }
            encoding = .utf16BigEndian
            units = stride(from: 2, to: bytes.count, by: 2).map {
                UInt32(bytes[$0]) << 8 | UInt32(bytes[$0 + 1])
            }
        } else {
            let bomLength = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
            let body = Data(bytes.dropFirst(bomLength))
            encoding = String(data: body, encoding: .utf8) != nil
                ? .utf8(bomLength: bomLength)
                : .isoLatin1
            units = bytes.dropFirst(bomLength).map(UInt32.init)
        }
    }

    var decodedString: String? {
        switch encoding {
        case .utf8:
            String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        case .isoLatin1:
            String(data: data, encoding: .isoLatin1)
        case .utf16LittleEndian:
            String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        case .utf16BigEndian:
            String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
    }

    var lineEnding: String {
        for index in units.indices where units[index] == 0x0A {
            return index > 0 && units[index - 1] == 0x0D ? "\r\n" : "\n"
        }
        return units.contains(0x0D) ? "\r" : "\n"
    }

    func byteOffset(forUnit index: Int) -> Int {
        switch encoding {
        case let .utf8(bomLength): bomLength + index
        case .isoLatin1: index
        case .utf16LittleEndian, .utf16BigEndian: 2 + index * 2
        }
    }

    func byteRange(forUnits range: Range<Int>) -> Range<Int> {
        byteOffset(forUnit: range.lowerBound)..<byteOffset(forUnit: range.upperBound)
    }

    func string(forUnits range: Range<Int>) -> String {
        let byteRange = byteRange(forUnits: range)
        let slice = data.subdata(in: byteRange)
        switch encoding {
        case .utf8:
            return String(data: slice, encoding: .utf8)
                ?? String(data: slice, encoding: .isoLatin1)
                ?? ""
        case .isoLatin1:
            return String(data: slice, encoding: .isoLatin1) ?? ""
        case .utf16LittleEndian:
            return String(data: slice, encoding: .utf16LittleEndian) ?? ""
        case .utf16BigEndian:
            return String(data: slice, encoding: .utf16BigEndian) ?? ""
        }
    }

    func encode(_ string: String) throws -> Data {
        let encoded: Data?
        switch encoding {
        case .utf8:
            encoded = string.data(using: .utf8)
        case .isoLatin1:
            encoded = string.data(using: .isoLatin1)
        case .utf16LittleEndian:
            encoded = string.data(using: .utf16LittleEndian)
        case .utf16BigEndian:
            encoded = string.data(using: .utf16BigEndian)
        }
        guard let encoded else { throw JoboptionsError.unsupportedEncoding }
        return encoded
    }
}
