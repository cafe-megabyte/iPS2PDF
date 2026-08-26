import Foundation
import PDFKit

actor MacOSDocumentWorkspace {
    private let directoryURL: URL

    init(identifier: UUID = UUID(), fileManager: FileManager = .default) {
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("iPS2PDF", isDirectory: true)
            .appendingPathComponent("MacOS Documents", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true)
    }

    func stageInput(from sourceURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
        guard values.isRegularFile == true,
              fileManager.isReadableFile(atPath: sourceURL.path)
        else {
            throw ConversionFailure.inputCannotBeRead
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let suffix = sourceURL.pathExtension.isEmpty ? "" : ".\(sourceURL.pathExtension)"
        let destinationURL = directoryURL.appendingPathComponent("input\(suffix)")
        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw ConversionFailure.inputCopy
        }
        return destinationURL
    }

    func writeJoboptions(_ data: Data) throws -> URL {
        let url = directoryURL.appendingPathComponent("Active.joboptions")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func outputURL(sourceName: String) -> URL {
        let stem = URL(fileURLWithPath: sourceName)
            .deletingPathExtension()
            .lastPathComponent
        return directoryURL
            .appendingPathComponent(stem.isEmpty ? "output" : stem)
            .appendingPathExtension("pdf")
    }

    func validatePDF(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ConversionFailure.outputMissing }
        guard (values.fileSize ?? 0) > 0 else { throw ConversionFailure.outputEmpty }
        guard PDFDocument(url: url) != nil else { throw ConversionFailure.invalidPDF }
    }

    func clear() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }
    }
}
