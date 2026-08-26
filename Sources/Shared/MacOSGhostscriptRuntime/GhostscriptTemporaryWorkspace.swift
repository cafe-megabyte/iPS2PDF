import Foundation

enum GhostscriptTemporaryWorkspace {
    static func create(purpose: String) throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("iPS2PDF-\(purpose)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        removeExpiredDirectories(in: root, fileManager: fileManager)

        let workspace = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: false)
        return workspace
    }

    private static func removeExpiredDirectories(in root: URL, fileManager: FileManager) {
        let expirationDate = Date().addingTimeInterval(-24 * 60 * 60)
        let candidates = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for candidate in candidates {
            guard let values = try? candidate.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            ),
                  values.isDirectory == true,
                  values.contentModificationDate.map({ $0 < expirationDate }) == true
            else { continue }
            try? fileManager.removeItem(at: candidate)
        }
    }
}

