import Foundation
import PDFKit

actor WorkingDirectoryService {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("Current conversion", isDirectory: true)
    }

    func clearWorkingDirectory() throws {
        do {
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw ConversionFailure.workingDirectoryCleanup
        }
    }

    func copySourceFile(from sourceURL: URL) throws -> URL {
        let startedAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if startedAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values: URLResourceValues
        do {
            values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            throw ConversionFailure.inputCannotBeRead
        }

        guard values.isRegularFile == true else {
            throw ConversionFailure.inputIsNotRegularFile
        }

        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw ConversionFailure.inputCannotBeRead
        }

        let localURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            try fileManager.copyItem(at: sourceURL, to: localURL)
            return localURL
        } catch {
            throw ConversionFailure.inputCopy
        }
    }

    func removeDropStagingDirectory(_ stagingDirectoryURL: URL) {
        let expectedParent = fileManager.temporaryDirectory
            .appendingPathComponent("Incoming drops", isDirectory: true)
            .standardizedFileURL

        guard stagingDirectoryURL.standardizedFileURL.deletingLastPathComponent() == expectedParent else {
            return
        }

        try? fileManager.removeItem(at: stagingDirectoryURL)
    }

    func outputURL(for localSourceURL: URL) -> URL {
        var outputURL = localSourceURL
        let extensionValue = outputURL.pathExtension

        if extensionValue.isEmpty {
            outputURL.appendPathExtension("pdf")
        } else if extensionValue.caseInsensitiveCompare("pdf") == .orderedSame {
            outputURL.appendPathExtension("pdf")
        } else {
            outputURL.deletePathExtension()
            outputURL.appendPathExtension("pdf")
        }

        return outputURL
    }

    func validatePDF(at outputURL: URL) throws {
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw ConversionFailure.outputMissing
        }

        let size: Int
        do {
            size = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        } catch {
            throw ConversionFailure.outputMissing
        }

        guard size > 0 else {
            throw ConversionFailure.outputEmpty
        }

        guard PDFDocument(url: outputURL) != nil else {
            throw ConversionFailure.invalidPDF
        }
    }
}
