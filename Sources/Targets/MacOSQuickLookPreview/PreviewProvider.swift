import QuickLookUI
import os

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        do {
            let workspace = try GhostscriptTemporaryWorkspace.create(purpose: "QuickLook")
            let outputURL = workspace.appendingPathComponent("Preview.pdf")
            guard let joboptionsURL = GhostscriptRuntimeResources.normalJoboptionsURL else {
                throw GhostscriptRuntimeConversion.Failure.missingResource("Normal.joboptions")
            }
            try GhostscriptRuntimeConversion.convert(
                inputURL: request.fileURL,
                outputURL: outputURL,
                joboptionsURL: joboptionsURL,
                pageSelection: .all
            )
            let reply = QLPreviewReply(fileURL: outputURL)
            reply.title = request.fileURL.lastPathComponent
            return reply
        } catch {
            Self.logger.error("Preview generation failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static let logger = Logger(
        subsystem: "de.cafe-megabyte.iPS2PDF.MacOS.QuickLook",
        category: "Preview"
    )
}
