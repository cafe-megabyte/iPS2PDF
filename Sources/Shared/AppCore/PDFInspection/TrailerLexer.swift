import Foundation

struct TrailerLexer {
    private let bytes: [UInt8]
    private var index = 0
    init(data: Data) { bytes = Array(data) }
    private var end: Bool { index >= bytes.count }
    private func isDelimiter(_ byte: UInt8) -> Bool { [0, 9, 10, 12, 13, 32, 40, 41, 60, 62, 91, 93, 123, 125, 47, 37].contains(byte) }
    private mutating func whitespace() {
        while !end {
            if [0, 9, 10, 12, 13, 32].contains(bytes[index]) { index += 1 }
            else if bytes[index] == 37 { while !end, bytes[index] != 10, bytes[index] != 13 { index += 1 } }
            else { break }
        }
    }
    mutating func token() throws -> String {
        whitespace()
        guard !end else { throw CocoaError(.fileReadCorruptFile) }
        let start = index; index += 1
        if bytes[start] == 60 || bytes[start] == 62 {
            if !end, bytes[index] == bytes[start] { index += 1 }
        } else if bytes[start] == 47 || !isDelimiter(bytes[start]) {
            while !end, !isDelimiter(bytes[index]) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
    mutating func dictionary() throws -> [String: String] {
        guard try token() == "<<" else { throw CocoaError(.fileReadCorruptFile) }
        var result: [String: String] = [:]
        while true {
            let name = try token()
            if name == ">>" { return result }
            guard name.hasPrefix("/"), result.count < 10_000 else { throw CocoaError(.fileReadCorruptFile) }
            let decoded = name.dropFirst().replacingOccurrences(of: "#([0-9A-Fa-f]{2})", with: "%$1", options: .regularExpression).removingPercentEncoding ?? String(name.dropFirst())
            result[decoded] = try value(depth: 0)
        }
    }
    private mutating func value(depth: Int) throws -> String {
        guard depth < 32 else { throw CocoaError(.fileReadCorruptFile) }
        whitespace(); let start = index
        let first = try token()
        if first == "(" {
            var nesting = 1
            while !end, nesting > 0 {
                let byte = bytes[index]; index += 1
                if byte == 92 { if !end { index += 1 } }
                else if byte == 40 { nesting += 1 }
                else if byte == 41 { nesting -= 1 }
            }
            guard nesting == 0 else { throw CocoaError(.fileReadCorruptFile) }
        } else if first == "<" {
            while !end, bytes[index] != 62 { index += 1 }
            guard !end else { throw CocoaError(.fileReadCorruptFile) }; index += 1
        } else if first == "<<" || first == "[" {
            let terminator = first == "<<" ? ">>" : "]"
            while true {
                let saved = index
                if try token() == terminator { break }
                index = saved; _ = try value(depth: depth + 1)
            }
        } else if Int(first) != nil {
            let saved = index
            if let next = try? token(), Int(next) != nil, (try? token()) == "R" { }
            else { index = saved }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
}
