import Foundation

struct GhostscriptProfileResolver {
    enum Failure: LocalizedError {
        case ambiguous(String)
        case missing(String)

        var errorDescription: String? {
            switch self {
            case .ambiguous(let name):
                "The bundled ICC profile name \(name) is ambiguous."
            case .missing(let name):
                "The bundled ICC profile \(name) is unavailable."
            }
        }
    }

    private let profilesByFilename: [String: URL]
    private let profilesByDescription: [String: [URL]]

    init(directoryURL: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            let pathExtension = url.pathExtension.lowercased()
            guard pathExtension == "icc" || pathExtension == "icm" else { return false }
            return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }

        var byFilename: [String: URL] = [:]
        var byDescription: [String: [URL]] = [:]
        for url in urls {
            byFilename[Self.key(url.deletingPathExtension().lastPathComponent)] = url
            for description in (try? ICCProfileDescriptionReader.descriptions(at: url)) ?? [] {
                byDescription[Self.key(description), default: []].append(url)
            }
        }
        profilesByFilename = byFilename
        profilesByDescription = byDescription
    }

    func resolve(_ name: String) throws -> URL {
        let lookupKey = Self.key(name)
        if let exact = profilesByFilename[lookupKey] {
            return exact
        }
        if let preferredFilename = Self.preferredFilenames[lookupKey],
           let preferred = profilesByFilename[Self.key(
               URL(fileURLWithPath: preferredFilename).deletingPathExtension().lastPathComponent
           )] {
            return preferred
        }
        let matches = profilesByDescription[lookupKey] ?? []
        guard !matches.isEmpty else { throw Failure.missing(name) }
        guard matches.count == 1 else { throw Failure.ambiguous(name) }
        return matches[0]
    }

    private static func key(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static let preferredFilenames = [
        key("Gray Gamma 2.2"): "Generic Gray Gamma 2.2 Profile.icc",
        key("sRGB IEC61966-2.1"): "sRGB Profile.icc"
    ]
}
