import Foundation
import PDFKit

actor WorkingDirectoryService {
    private static let stagingDirectoryNames = ["Incoming drops", "Incoming shares"]

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
                AppGroupWorkspace.prepareForRemoval(at: directoryURL, fileManager: fileManager)
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
            try AppGroupWorkspace.cloneFileForConversion(
                from: sourceURL,
                to: localURL,
                fileManager: fileManager
            )
            return localURL
        } catch {
            throw ConversionFailure.inputCopy(diagnostics: error.localizedDescription)
        }
    }

    func removeStagingDirectory(_ stagingDirectoryURL: URL) {
        let expectedParents = Self.stagingDirectoryNames.map {
            fileManager.temporaryDirectory
                .appendingPathComponent($0, isDirectory: true)
                .standardizedFileURL
        }
        let actualParent = stagingDirectoryURL.standardizedFileURL.deletingLastPathComponent()

        guard expectedParents.contains(actualParent) else {
            return
        }

        try? fileManager.removeItem(at: stagingDirectoryURL)
    }

    static func clearStaleStagingDirectories(fileManager: FileManager = .default) throws {
        for directoryName in stagingDirectoryNames {
            let directoryURL = fileManager.temporaryDirectory
                .appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: directoryURL.path) else { continue }
            AppGroupWorkspace.prepareForRemoval(at: directoryURL, fileManager: fileManager)
            try fileManager.removeItem(at: directoryURL)
        }
    }

    func outputURL(for localSourceURL: URL) throws -> URL {
        let outputDirectoryURL = directoryURL.appendingPathComponent("Output", isDirectory: true)
        do {
            try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw ConversionFailure.workingDirectoryCleanup
        }
        return outputDirectoryURL
            .appendingPathComponent(localSourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
    }

    func writeJoboptionsSnapshot(_ data: Data) throws -> URL {
        let snapshotURL = directoryURL.appendingPathComponent("Active.joboptions")
        do {
            try data.write(to: snapshotURL, options: [.atomic])
            return snapshotURL
        } catch {
            throw JoboptionsError.writeFailed
        }
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
