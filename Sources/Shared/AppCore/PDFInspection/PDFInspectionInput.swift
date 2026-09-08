import Darwin
import Foundation

/// An immutable byte-for-byte snapshot, retained by every reader until it has finished.
final class PDFInspectionInput: @unchecked Sendable {
    let url: URL
    let fileName: String
    private(set) var fileDates: (created: Date?, modified: Date?) = (nil, nil)
    private let directory: URL
    private let fileManager: FileManager

    init(sourceURL: URL, displayFileName: String? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        fileName = displayFileName ?? sourceURL.lastPathComponent
        directory = Self.rootDirectory(fileManager: fileManager)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotName = fileName.isEmpty || fileName.contains("/") || fileName == "." || fileName == ".." ? "Document.pdf" : fileName
        url = directory.appendingPathComponent(snapshotName)
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                guard try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let values = try coordinatedURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                fileDates = (values.creationDate, values.contentModificationDate)
                try fileManager.copyItem(at: coordinatedURL, to: url)
            } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? {
            try? fileManager.removeItem(at: directory)
            Self.removeRootIfEmpty(fileManager: fileManager)
            throw error
        }
    }

    static func clearStaleDirectories(fileManager: FileManager = .default) throws {
        let root = rootDirectory(fileManager: fileManager)
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    private static func rootDirectory(fileManager: FileManager) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent("PDFInspection", isDirectory: true)
    }

    private static func removeRootIfEmpty(fileManager: FileManager) {
        rootDirectory(fileManager: fileManager).withUnsafeFileSystemRepresentation { path in
            if let path { _ = Darwin.rmdir(path) }
        }
    }

    deinit {
        try? fileManager.removeItem(at: directory)
        Self.removeRootIfEmpty(fileManager: fileManager)
    }
}
