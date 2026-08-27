import Foundation

enum DroppedFileStaging {
    static let directoryName = "Incoming drops"

    static func stage(_ temporaryURL: URL, suggestedName: String?) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let proposedName = suggestedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? temporaryURL.lastPathComponent
        let fileName = URL(fileURLWithPath: proposedName).lastPathComponent
        let stagedURL = directoryURL.appendingPathComponent(fileName)
        do {
            try AppGroupWorkspace.cloneFileForConversion(
                from: temporaryURL,
                to: stagedURL,
                fileManager: fileManager
            )
            return stagedURL
        } catch {
            AppGroupWorkspace.prepareForRemoval(at: directoryURL, fileManager: fileManager)
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }
}
