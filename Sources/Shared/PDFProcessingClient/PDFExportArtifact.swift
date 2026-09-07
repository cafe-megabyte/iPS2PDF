import Foundation

final class PDFExportArtifact: @unchecked Sendable {
    let url: URL
    private let directory: URL

    init(copying source: URL, filename: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFResourceExport", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        url = directory.appendingPathComponent(filename)
        do { try FileManager.default.copyItem(at: source, to: url) }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
