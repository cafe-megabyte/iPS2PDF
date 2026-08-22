import Foundation

enum EnhancedSecurityDirectoryProbe {
    private static let prefix = "🧭 iPS2PDF-ES"

    static func run(fileManager: FileManager = .default) {
        let report = report(fileManager: fileManager)
        for line in report.components(separatedBy: "\n") where !line.isEmpty {
            log(line)
        }
    }

    static func report(fileManager: FileManager = .default) -> String {
        var lines = [
            "directory probe begin",
            "NSHomeDirectory=\(NSHomeDirectory())",
            "temporaryDirectory=\(fileManager.temporaryDirectory.path)",
            "NSTemporaryDirectory=\(NSTemporaryDirectory())",
            "currentDirectoryPath=\(fileManager.currentDirectoryPath)"
        ]

        for candidate in candidates(fileManager: fileManager) {
            lines.append(probe(label: candidate.label, baseURL: candidate.url, fileManager: fileManager))
        }
        lines.append("directory probe end")
        return lines.joined(separator: "\n")
    }

    private static func candidates(fileManager: FileManager) -> [(label: String, url: URL)] {
        var candidates: [(String, URL)] = [
            ("temporaryDirectory", fileManager.temporaryDirectory),
            ("NSTemporaryDirectory", URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)),
            ("NSHomeDirectory", URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)),
            ("currentDirectoryPath", URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))
        ]

        candidates.append(contentsOf: urls(for: .documentDirectory, label: "Documents", fileManager: fileManager))
        candidates.append(contentsOf: urls(for: .libraryDirectory, label: "Library", fileManager: fileManager))
        candidates.append(contentsOf: urls(for: .cachesDirectory, label: "Caches", fileManager: fileManager))
        candidates.append(contentsOf: urls(for: .applicationSupportDirectory, label: "ApplicationSupport", fileManager: fileManager))
        candidates.append(contentsOf: urls(for: .itemReplacementDirectory, label: "ItemReplacement", fileManager: fileManager))

        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.1.standardizedFileURL.path).inserted
        }.map { candidate in
            (label: candidate.0, url: candidate.1)
        }
    }

    private static func urls(
        for directory: FileManager.SearchPathDirectory,
        label: String,
        fileManager: FileManager
    ) -> [(label: String, url: URL)] {
        let urls = fileManager.urls(for: directory, in: .userDomainMask)
        if urls.isEmpty {
            log("\(label) urls=<empty>")
        }
        return urls.enumerated().map { index, url in
            ("\(label)[\(index)]", url)
        }
    }

    private static func probe(label: String, baseURL: URL, fileManager: FileManager) -> String {
        let probeDirectory = baseURL
            .appendingPathComponent("iPS2PDF-DirectoryProbe-\(UUID().uuidString)", isDirectory: true)
        let probeFile = probeDirectory.appendingPathComponent("write-test.txt")
        do {
            try fileManager.createDirectory(at: probeDirectory, withIntermediateDirectories: true)
            let bytes = Data("iPS2PDF Enhanced Security write probe\n".utf8)
            try bytes.write(to: probeFile, options: .completeFileProtectionUnlessOpen)
            let size = try probeFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
            try fileManager.removeItem(at: probeDirectory)
            return "probe label=\(label) writable=true base=\(baseURL.path) fileSize=\(size)"
        } catch {
            try? fileManager.removeItem(at: probeDirectory)
            return "probe label=\(label) writable=false base=\(baseURL.path) error=\(error.localizedDescription)"
        }
    }

    private static func log(_ message: String) {
        NSLog("%@ %@", prefix, message)
    }
}
