import Foundation

enum PDFResourceExporter {
    enum DestinationAccess: Sendable {
        case exactItem
        case parentDirectory
    }

    struct Progress: Sendable {
        let completed: Int
        let total: Int
        let filename: String
    }

    static func extract(_ resource: PDFExtractableResource, from session: PDFInspectionSession) async throws -> PDFExportArtifact {
        let context = await MainActor.run { (session.report.allowsResourceExporting, session.currentInput, session.unlockedPassword) }
        guard context.0, let input = context.1 else {
            throw CocoaError(.fileReadNoPermission)
        }
        return try await PDFProcessingClient().extract(resource, input: input, password: context.2)
    }

    static func exportAll(_ resources: [PDFExtractableResource], from session: PDFInspectionSession,
                          to destination: URL,
                          destinationAccess: DestinationAccess = .parentDirectory,
                          progress: @escaping @Sendable (Progress) async -> Void = { _ in }) async throws {
        let context = await MainActor.run { (session.report.allowsResourceExporting, session.currentInput, session.unlockedPassword) }
        guard context.0, let input = context.1, !resources.isEmpty else {
            throw CocoaError(.fileReadNoPermission)
        }
        let password = context.2
        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFResourceFolders", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: stageRoot, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stageRoot) }
        var usedNames: [PDFExtractableResourceKind: Set<String>] = [:]
        for (index, resource) in resources.enumerated() {
            try Task.checkCancellation()
            await progress(Progress(completed: index, total: resources.count, filename: resource.suggestedFilename))
            let artifact = try await PDFProcessingClient().extract(resource, input: input, password: password)
            let folder = stageRoot.appendingPathComponent(resource.kind.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let filename = uniqueFilename(resource.suggestedFilename, used: &usedNames[resource.kind, default: []])
            try FileManager.default.copyItem(at: artifact.url, to: folder.appendingPathComponent(filename))
        }
        await progress(Progress(completed: resources.count, total: resources.count, filename: ""))
        try Task.checkCancellation()
        switch destinationAccess {
        case .exactItem:
            try installAtExactDestination(stageRoot, at: destination)
        case .parentDirectory:
            try installDirectory(stageRoot, at: destination)
        }
    }

    static func copy(_ artifact: PDFExportArtifact, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: artifact.url)
        } else {
            try FileManager.default.copyItem(at: artifact.url, to: destination)
        }
    }

    static func defaultFolderName(for fileName: String) -> String {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return PDFResourceDescriptorFactory.sanitizedName(base, fallback: "PDF") + " Resources"
    }

    static func availableDirectory(named name: String, in parent: URL) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private static func uniqueFilename(_ proposed: String, used: inout Set<String>) -> String {
        let safe = PDFResourceDescriptorFactory.sanitizedName(proposed, fallback: "Resource")
        let url = URL(fileURLWithPath: safe)
        let ext = url.pathExtension
        let stem = ext.isEmpty ? safe : String(safe.dropLast(ext.count + 1))
        var result = safe
        var suffix = 2
        while !used.insert(result.lowercased()).inserted {
            result = stem + "-\(suffix)" + (ext.isEmpty ? "" : "." + ext)
            suffix += 1
        }
        return result
    }

    private static func installDirectory(_ staged: URL, at destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let sibling = parent.appendingPathComponent(".ips2pdf-resources-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        try FileManager.default.copyItem(at: staged, to: sibling)
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: sibling)
        } else {
            try FileManager.default.moveItem(at: sibling, to: destination)
        }
    }

    private static func installAtExactDestination(_ staged: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
        } else {
            try FileManager.default.copyItem(at: staged, to: destination)
        }
    }
}
