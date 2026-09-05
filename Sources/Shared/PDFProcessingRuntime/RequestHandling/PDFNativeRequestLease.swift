import Darwin
import Foundation

/// Serializes both native engines across helper instances and host processes.
/// A crashed helper releases the advisory lock automatically.
final class PDFNativeRequestLease {
    private let descriptor: Int32
    static func acquire(library: URL? = nil) throws -> PDFNativeRequestLease? {
        let library = try library ?? AppGroup.containerURL().appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let fd = Darwin.open(library.appendingPathComponent("NativePDFEngine.lock").path,
                             O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        var status = stat()
        guard fstat(fd, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(fd); throw CocoaError(.fileReadNoPermission)
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK
            Darwin.close(fd)
            if busy { return nil }
            throw CocoaError(.fileReadNoPermission)
        }
        return PDFNativeRequestLease(descriptor: fd)
    }
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
