import Foundation

struct ICCProfileRecord: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable {
        case bundled
        case user
    }

    let id: String
    let name: String
    let origin: Origin
    let url: URL
    let profileClass: String
    let colorSpace: String
    let connectionSpace: String

    var isBundled: Bool { origin == .bundled }

    static func inspect(url: URL, origin: Origin) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 128), header.count == 128 else {
            throw ICCProfileError.invalidHeader
        }
        let bytes = [UInt8](header)
        let declaredSize = bytes[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        let actualSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard declaredSize >= 128, declaredSize <= actualSize,
              String(bytes: bytes[36..<40], encoding: .ascii) == "acsp"
        else {
            throw ICCProfileError.invalidHeader
        }

        func signature(_ range: Range<Int>) -> String {
            String(bytes: bytes[range], encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let prefix = origin == .bundled ? "bundled" : "user"
        return Self(
            id: "\(prefix):\(url.lastPathComponent)",
            name: url.deletingPathExtension().lastPathComponent,
            origin: origin,
            url: url,
            profileClass: signature(12..<16),
            colorSpace: signature(16..<20),
            connectionSpace: signature(20..<24)
        )
    }
}

enum ICCProfileError: LocalizedError {
    case invalidHeader

    var errorDescription: String? {
        String(localized: "The file does not contain a valid ICC profile header.")
    }
}
