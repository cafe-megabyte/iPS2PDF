import Foundation

/// NSDocument can save off the main thread. A save retains one complete
/// revision while the UI may accept another edit or evict its undo history.
final class PDFEditingSnapshotStore: @unchecked Sendable {
    private let lock = NSLock()
    private var revision: PDFEditingRevision?
    func store(_ revision: PDFEditingRevision?) {
        lock.lock(); self.revision = revision; lock.unlock()
    }
    func value() -> PDFEditingRevision? {
        lock.lock(); defer { lock.unlock() }; return revision
    }
}
