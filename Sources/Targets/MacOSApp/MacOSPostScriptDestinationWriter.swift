import Foundation

enum MacOSPostScriptDestinationWriter {
    static func publish(sourceURL: URL, destinationURL: URL) throws {
        let fileManager = FileManager.default
        let access = destinationURL.startAccessingSecurityScopedResource()
        defer { if access { destinationURL.stopAccessingSecurityScopedResource() } }

        // NSSavePanel grants sandbox access to the selected item, not to an
        // arbitrary sibling such as "output.ps.partial". Ghostscript has
        // already completed into the private workspace, so install that
        // finished file directly at the exact destination selected by the user.
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: sourceURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
    }
}
