import Foundation

/// An immutable byte-for-byte snapshot, retained by every reader until it has finished.
final class PDFInspectionInput: @unchecked Sendable {
    let url: URL
    let fileName: String
    private(set) var fileDates: (created: Date?, modified: Date?) = (nil, nil)
    private let directory: URL

    init(sourceURL: URL, displayFileName: String? = nil) throws {
        fileName = displayFileName ?? sourceURL.lastPathComponent
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PDFInspection", isDirectory: true).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotName = fileName.isEmpty || fileName.contains("/") || fileName == "." || fileName == ".." ? "Document.pdf" : fileName
        url = directory.appendingPathComponent(snapshotName)
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                guard try coordinatedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
                let values = try coordinatedURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                fileDates = (values.creationDate, values.contentModificationDate)
                try FileManager.default.copyItem(at: coordinatedURL, to: url)
            } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError as NSError? {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    deinit { try? FileManager.default.removeItem(at: directory) }
}
