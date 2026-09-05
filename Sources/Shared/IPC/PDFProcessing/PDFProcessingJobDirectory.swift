import Darwin
import Foundation

/// One private directory per request. Sender and helper hold shared file locks;
/// cleanup requires an exclusive lock and cannot invalidate an active request.
final class PDFProcessingJobDirectory: @unchecked Sendable {
    let id: UUID
    let url: URL
    var inputURL: URL { url.appendingPathComponent("input.pdf") }
    var outputURL: URL { url.appendingPathComponent("result.pdf") }
    private let descriptor: Int32

    static func rootURL() throws -> URL {
        // Library is excluded from the existing conversion workspace cleanup.
        // New PDF jobs therefore survive unrelated Share/conversion cleanup.
        try AppGroup.containerURL()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("PDFProcessingJobs", isDirectory: true)
    }

    static func create(root: URL? = nil) throws -> PDFProcessingJobDirectory {
        let root = try root ?? rootURL()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let id = UUID()
        let url = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        do { return try PDFProcessingJobDirectory(id: id, url: url, create: true) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    static func open(id: UUID, root: URL? = nil) throws -> PDFProcessingJobDirectory {
        let root = try root ?? rootURL()
        return try PDFProcessingJobDirectory(id: id, url: root.appendingPathComponent(id.uuidString, isDirectory: true), create: false)
    }

    private init(id: UUID, url: URL, create: Bool) throws {
        self.id = id
        self.url = url
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
        let lease = url.appendingPathComponent("lease")
        let fd = Darwin.open(lease.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | (create ? O_CREAT | O_EXCL : 0), 0o600)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG,
              flock(fd, LOCK_SH | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw CocoaError(.fileReadNoPermission)
        }
        descriptor = fd
    }

    static func removeStaleJobs(root: URL? = nil, now: Date = Date()) throws {
        let root = try root ?? rootURL()
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey]) {
            guard UUID(uuidString: url.lastPathComponent) != nil else { continue }
            let values = try url.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  let created = values.creationDate, now.timeIntervalSince(created) > 10 * 60 else { continue }
            if !FileManager.default.fileExists(atPath: url.appendingPathComponent("lease").path) {
                // A crash between mkdir and lease creation leaves no active
                // request. The age check excludes a newly creating sender.
                try? FileManager.default.removeItem(at: url)
            } else { removeIfUnused(url) }
        }
    }

    private static func removeIfUnused(_ url: URL) {
        let fd = Darwin.open(url.appendingPathComponent("lease").path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { return }
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
        Self.removeIfUnused(url)
    }
}
