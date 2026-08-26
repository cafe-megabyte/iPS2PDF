import Foundation

/// Persistent storage owned only by the containing app.
enum ApplicationStorage {
    static func userJoboptionsDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Joboptions", isDirectory: true)
    }

    static func userProfilesDirectory(fileManager: FileManager = .default) throws -> URL {
        try applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    private static func applicationSupportDirectory(fileManager: FileManager) throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directoryURL = baseURL.appendingPathComponent("iPS2PDF", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
