import Foundation

/// Minimal ICC metadata reader used by the extension.
struct ICCProfileRecord: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable {
        case bundled
        case user
    }

    let id: String
    let name: String
    let fileStem: String
    let origin: Origin
    let url: URL
    let profileClass: String
    let colorSpace: String
    let connectionSpace: String

    var isBundled: Bool { origin == .bundled }
    func matches(_ value: String) -> Bool { name == value || fileStem == value }

    static func inspect(url: URL, origin: Origin) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let header = try handle.read(upToCount: 128), header.count == 128 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let bytes = [UInt8](header)
        let declaredSize = bytes[0..<4].reduce(0) { ($0 << 8) | Int($1) }
        let actualSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard declaredSize >= 128, declaredSize <= actualSize,
              String(bytes: bytes[36..<40], encoding: .ascii) == "acsp"
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        func signature(_ range: Range<Int>) -> String {
            String(bytes: bytes[range], encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let prefix = origin == .bundled ? "bundled" : "user"
        let fileStem = url.deletingPathExtension().lastPathComponent
        let displayName = (try? ICCProfileDescriptionReader.descriptions(at: url).first) ?? fileStem
        return Self(
            id: "\(prefix):\(url.lastPathComponent)",
            name: displayName,
            fileStem: fileStem,
            origin: origin,
            url: url,
            profileClass: signature(12..<16),
            colorSpace: signature(16..<20),
            connectionSpace: signature(20..<24)
        )
    }
}
