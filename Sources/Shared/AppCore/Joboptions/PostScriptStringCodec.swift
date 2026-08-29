import Foundation

enum PostScriptStringCodec {
    enum Representation: Equatable, Sendable {
        case literal
        case hexadecimal
    }

    static func decodeLiteral(_ source: String) -> String {
        let characters = Array(source)
        var result = ""
        var index = 0

        while index < characters.count {
            guard characters[index] == "\\" else {
                result.append(characters[index])
                index += 1
                continue
            }

            index += 1
            guard index < characters.count else {
                result.append("\\")
                break
            }

            switch characters[index] {
            case "n": result.append("\n"); index += 1
            case "r": result.append("\r"); index += 1
            case "t": result.append("\t"); index += 1
            case "b": result.append("\u{08}"); index += 1
            case "f": result.append("\u{0C}"); index += 1
            case "\n": index += 1
            case "\r":
                index += 1
                if index < characters.count, characters[index] == "\n" { index += 1 }
            case "0"..."7":
                var digits = ""
                while index < characters.count,
                      digits.count < 3,
                      ("0"..."7").contains(characters[index]) {
                    digits.append(characters[index])
                    index += 1
                }
                if let scalar = UInt8(digits, radix: 8) {
                    result.unicodeScalars.append(UnicodeScalar(scalar))
                }
            default:
                result.append(characters[index])
                index += 1
            }
        }
        return result
    }

    static func decodeHexadecimal(_ source: String) -> String? {
        let digits = source.filter { !$0.isWhitespace }
        guard !digits.isEmpty else { return "" }
        let padded = digits.count.isMultiple(of: 2) ? digits : digits + "0"
        var bytes: [UInt8] = []
        var index = padded.startIndex
        while index < padded.endIndex {
            let next = padded.index(index, offsetBy: 2)
            guard let byte = UInt8(padded[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        let data = Data(bytes)
        if bytes.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        return String(data: data, encoding: .isoLatin1)
    }

    static func encodeLiteral(_ value: String) -> String {
        var result = ""
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "(": result += "\\("
            case ")": result += "\\)"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default: result.append(character)
            }
        }
        return "(\(result))"
    }

    static func encodeAdobeUnicodeHex(_ value: String) -> String {
        let data = value.data(using: .utf16BigEndian) ?? Data()
        return "<FEFF\(data.map { String(format: "%02X", $0) }.joined())>"
    }
}
