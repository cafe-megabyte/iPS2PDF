import Foundation

/// Fixed, single-job storage shared by the app and both extensions.
enum AppGroupWorkspace {
    static let shareDirectoryName = "ShareInbox"
    static let inputDirectoryName = "ConversionInput"
    static let outputDirectoryName = "ConversionOutput"

    static let sharedTextFileName = "SharedText.ps"
    static let inputFileName = "input"
    static let joboptionsFileName = "Active.joboptions"
    static let profilesDirectoryName = "Profiles"
    static let readyFileName = "ready"
    static let outputFileName = "output.pdf"
    static let partialOutputFileName = "output.pdf.partial"
    static let journalFileName = "journal.log"
    static let partialJournalFileName = "journal.log.partial"

    static func containerURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        try containerURL ?? AppGroup.containerURL(fileManager: fileManager)
    }

    static func shareDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        try self.containerURL(fileManager: fileManager, containerURL: containerURL)
            .appendingPathComponent(shareDirectoryName, isDirectory: true)
    }

    static func inputDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        try self.containerURL(fileManager: fileManager, containerURL: containerURL)
            .appendingPathComponent(inputDirectoryName, isDirectory: true)
    }

    static func outputDirectoryURL(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws -> URL {
        try self.containerURL(fileManager: fileManager, containerURL: containerURL)
            .appendingPathComponent(outputDirectoryName, isDirectory: true)
    }

    static func prepareConversionDirectories(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws {
        try clearConversionDirectories(fileManager: fileManager, containerURL: containerURL)
        try fileManager.createDirectory(
            at: inputDirectoryURL(fileManager: fileManager, containerURL: containerURL),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: outputDirectoryURL(fileManager: fileManager, containerURL: containerURL),
            withIntermediateDirectories: true
        )
    }

    static func clearConversionDirectories(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws {
        for url in [
            try inputDirectoryURL(fileManager: fileManager, containerURL: containerURL),
            try outputDirectoryURL(fileManager: fileManager, containerURL: containerURL)
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Removes stale jobs and all historical shared state while preserving a
    /// newly delivered Share item until the main app has claimed it.
    static func clearStaleDataPreservingShareInbox(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws {
        let root = try self.containerURL(fileManager: fileManager, containerURL: containerURL)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children
        where child.lastPathComponent != shareDirectoryName && !isSystemManagedChild(child) {
            try fileManager.removeItem(at: child)
        }
    }

    static func clearAll(
        fileManager: FileManager = .default,
        containerURL: URL? = nil
    ) throws {
        let root = try self.containerURL(fileManager: fileManager, containerURL: containerURL)
        guard fileManager.fileExists(atPath: root.path) else { return }
        for child in try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        ) where !isSystemManagedChild(child) {
            try fileManager.removeItem(at: child)
        }
    }

    private static func isSystemManagedChild(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(".") || url.lastPathComponent == "Library"
    }

    static func publishFile(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let partialURL = destinationURL.appendingPathExtension("partial")
        try? fileManager.removeItem(at: partialURL)
        try fileManager.copyItem(at: sourceURL, to: partialURL)
        do {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
    }
}
