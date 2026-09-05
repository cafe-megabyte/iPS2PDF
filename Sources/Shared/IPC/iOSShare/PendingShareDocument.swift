import Foundation

enum PendingShareDocument {
    static let triggerURL = URL(string: "ips2pdf://share-pending")!

    private static let stagingDirectoryName = "Incoming shares"

    static func isTriggerURL(_ url: URL) -> Bool {
        url.scheme == triggerURL.scheme && url.host == triggerURL.host
    }

    static func writePostScript(
        _ text: String,
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        let directoryURL = try prepareDirectory(fileManager: fileManager, containerURL: containerURL)

        let sourceURL = directoryURL.appendingPathComponent(AppGroupWorkspace.sharedTextFileName)
        try text.write(to: sourceURL, atomically: true, encoding: .utf8)
        return sourceURL
    }

    static func writeFile(
        from sourceURL: URL,
        preferredFileName: String? = nil,
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        let directoryURL = try prepareDirectory(fileManager: fileManager, containerURL: containerURL)
        let fileName = safeFileName(preferredFileName ?? sourceURL.lastPathComponent)
        let destinationURL = directoryURL.appendingPathComponent(fileName)
        try AppGroupWorkspace.publishFile(
            from: sourceURL,
            to: destinationURL,
            fileManager: fileManager
        )
        return destinationURL
    }

    static func pendingSourceURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL? {
        let directoryURL = try directory(fileManager: fileManager, containerURL: containerURL)
        guard fileManager.fileExists(atPath: directoryURL.path) else { return nil }
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).first {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }
    }

    /// Claims the pending handoff exactly once and moves it into the main app's
    /// temporary container before conversion starts.
    static func claimPendingSourceURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil,
        stagingRootURL: URL? = nil
    ) throws -> URL? {
        guard let pendingURL = try pendingSourceURL(
            fileManager: fileManager,
            containerURL: containerURL
        ) else { return nil }

        let stagingDirectoryURL = stagingRootURL ?? fileManager.temporaryDirectory
            .appendingPathComponent(stagingDirectoryName, isDirectory: true)
        let claimedURL = stagingDirectoryURL.appendingPathComponent(pendingURL.lastPathComponent)

        AppGroupWorkspace.prepareForRemoval(at: stagingDirectoryURL, fileManager: fileManager)
        try? fileManager.removeItem(at: stagingDirectoryURL)
        try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
        do {
            try AppGroupWorkspace.cloneFileForConversion(
                from: pendingURL,
                to: claimedURL,
                fileManager: fileManager
            )
            let pendingDirectoryURL = try directory(
                fileManager: fileManager,
                containerURL: containerURL
            )
            AppGroupWorkspace.prepareForRemoval(
                at: pendingDirectoryURL,
                fileManager: fileManager
            )
            try fileManager.removeItem(at: pendingDirectoryURL)
            return claimedURL
        } catch {
            AppGroupWorkspace.prepareForRemoval(at: stagingDirectoryURL, fileManager: fileManager)
            try? fileManager.removeItem(at: stagingDirectoryURL)
            throw error
        }
    }

    static func remove(fileManager: FileManager = .default, containerURL: URL? = nil) {
        guard let directoryURL = try? directory(
            fileManager: fileManager,
            containerURL: containerURL
        ) else { return }
        AppGroupWorkspace.prepareForRemoval(at: directoryURL, fileManager: fileManager)
        try? fileManager.removeItem(at: directoryURL)
    }

    private static func directory(fileManager: FileManager, containerURL: URL?) throws -> URL {
        try AppGroupWorkspace.shareDirectoryURL(
            fileManager: fileManager,
            containerURL: containerURL
        )
    }

    private static func prepareDirectory(
        fileManager: FileManager,
        containerURL: URL?
    ) throws -> URL {
        let directoryURL = try directory(fileManager: fileManager, containerURL: containerURL)
        AppGroupWorkspace.prepareForRemoval(at: directoryURL, fileManager: fileManager)
        try? fileManager.removeItem(at: directoryURL)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func safeFileName(_ proposedName: String) -> String {
        let fileName = URL(fileURLWithPath: proposedName).lastPathComponent
        return fileName.isEmpty || fileName == "." ? "SharedDocument" : fileName
    }
}
