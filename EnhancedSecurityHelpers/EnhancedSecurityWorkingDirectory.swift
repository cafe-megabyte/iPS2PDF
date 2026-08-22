import Foundation

enum EnhancedSecurityWorkingDirectory {
    private static let logPrefix = "🧭 iPS2PDF-ES"

    static func create(fileManager: FileManager = .default) throws -> URL {
        var failures: [String] = []
        for baseURL in candidateBaseURLs(fileManager: fileManager) {
            let parentURL = baseURL.appendingPathComponent("iPS2PDF-Helper", isDirectory: true)
            let directoryURL = parentURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            log("workdir candidate base=\(baseURL.path) parent=\(parentURL.path)")
            do {
                try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)
                log("workdir selected path=\(directoryURL.path)")
                return directoryURL
            } catch {
                log("workdir rejected path=\(parentURL.path) error=\(error.localizedDescription)")
                failures.append("\(parentURL.path): \(error.localizedDescription)")
            }
        }
        throw EnhancedSecurityWorkingDirectoryError.noWritableDirectory(failures)
    }

    private static func candidateBaseURLs(fileManager: FileManager) -> [URL] {
        var urls: [URL] = []
        urls.append(URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        urls.append(fileManager.temporaryDirectory)
        urls.append(contentsOf: fileManager.urls(for: .cachesDirectory, in: .userDomainMask))
        urls.append(contentsOf: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask))
        urls.append(contentsOf: fileManager.urls(for: .libraryDirectory, in: .userDomainMask))
        urls.append(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))

        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.standardizedFileURL.path).inserted
        }
    }

    private static func log(_ message: String) {
        NSLog("%@ %@", logPrefix, message)
    }
}
