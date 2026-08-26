import Foundation

enum AppGroup {
    static let identifier = "group.de.cafe-megabyte.iPS2PDF"

    static func containerURL(fileManager: FileManager = .default) throws -> URL {
        guard let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw CocoaError(
                .fileNoSuchFile,
                userInfo: [
                    NSLocalizedDescriptionKey: String(
                        localized: "The shared App Group container is unavailable."
                    )
                ]
            )
        }
        return groupURL
    }
}
