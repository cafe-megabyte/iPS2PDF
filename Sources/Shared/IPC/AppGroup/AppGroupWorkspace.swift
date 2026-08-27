import Darwin
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
            prepareForRemoval(at: url, fileManager: fileManager)
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
            prepareForRemoval(at: child, fileManager: fileManager)
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
            prepareForRemoval(at: child, fileManager: fileManager)
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
        prepareForRemoval(at: partialURL, fileManager: fileManager)
        try? fileManager.removeItem(at: partialURL)
        try cloneFileForConversion(from: sourceURL, to: partialURL, fileManager: fileManager)
        do {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        } catch {
            prepareForRemoval(at: partialURL, fileManager: fileManager)
            try? fileManager.removeItem(at: partialURL)
            throw error
        }
    }

    static func cloneFileForConversion(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager = .default
    ) throws {
        prepareForRemoval(at: destinationURL, fileManager: fileManager)
        try? fileManager.removeItem(at: destinationURL)
        try sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            try destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }
                guard clonefile(sourcePath, destinationPath, UInt32(CLONE_NOFOLLOW)) == 0 else {
                    let cloneError = errno
                    try? fileManager.removeItem(at: destinationURL)
                    throw cloneFailure(sourceURL: sourceURL, errno: cloneError)
                }
            }
        }
        try sanitizeConversionFile(at: destinationURL)
    }

    static func prepareForRemoval(at url: URL, fileManager: FileManager = .default) {
        let children = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        for child in children {
            prepareForRemoval(at: child, fileManager: fileManager)
        }
        try? sanitizeConversionFile(at: url)
    }

    private static func sanitizeConversionFile(at url: URL) throws {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw CocoaError(.fileWriteInvalidFileName) }
            var metadata = stat()
            guard lstat(path, &metadata) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard metadata.st_mode & S_IFMT != S_IFLNK else { return }

            _ = chflags(path, 0)
            let mode = metadata.st_mode & S_IFMT == S_IFDIR
                ? S_IRWXU
                : S_IRUSR | S_IWUSR
            _ = chmod(path, mode)
            removeAccessControlList(at: path)
            try removeExtendedAttributes(at: path)
        }
    }

    private static func removeAccessControlList(at path: UnsafePointer<CChar>) {
        guard let emptyACL = acl_init(0) else { return }
        defer { acl_free(UnsafeMutableRawPointer(emptyACL)) }
        _ = acl_set_file(path, ACL_TYPE_EXTENDED, emptyACL)
    }

    private static func removeExtendedAttributes(at path: UnsafePointer<CChar>) throws {
        var size = listxattr(path, nil, 0, 0)
        guard size >= 0 else {
            if errno == ENOTSUP { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard size > 0 else { return }

        var buffer = [CChar](repeating: 0, count: size)
        size = listxattr(path, &buffer, buffer.count, 0)
        guard size >= 0 else {
            if errno == ENOTSUP { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var index = 0
        while index < size {
            let nameStart = index
            while index < size, buffer[index] != 0 {
                index += 1
            }
            guard index > nameStart else {
                index += 1
                continue
            }
            buffer.withUnsafeBufferPointer { pointer in
                if let baseAddress = pointer.baseAddress {
                    _ = removexattr(path, baseAddress.advanced(by: nameStart), 0)
                }
            }
            index += 1
        }
    }

    private static func cloneFailure(sourceURL: URL, errno: Int32) -> Error {
        let message: String
        switch errno {
        case ENOTSUP:
            message = "The file system does not support copy-on-write staging."
        case EXDEV:
            message = "The input file cannot be staged with copy-on-write across file systems."
        default:
            message = "Could not stage \(sourceURL.lastPathComponent) with copy-on-write: \(String(cString: strerror(errno)))."
        }
        return CocoaError(
            .fileWriteUnknown,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
