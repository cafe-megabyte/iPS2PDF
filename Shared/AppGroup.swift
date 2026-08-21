import Foundation

enum AppGroup {
    static let identifier = "group.de.cafe-megabyte.iPS2PDF"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static func containerURL(fileManager: FileManager = .default) throws -> URL {
        if let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) {
            return groupURL
        }

        // This fallback keeps previews and unsigned simulator builds usable.
        // Signed App Store builds always use the App Group container above.
        let fallback = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("iPS2PDF Shared", isDirectory: true)
        try fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }
}
