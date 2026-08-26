import CoreGraphics
import QuickLookThumbnailing
import os

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        do {
            let workspace = try GhostscriptTemporaryWorkspace.create(purpose: "Thumbnails")
            let outputURL = workspace.appendingPathComponent("Thumbnail.pdf")
            guard let joboptionsURL = GhostscriptRuntimeResources.normalJoboptionsURL else {
                throw GhostscriptRuntimeConversion.Failure.missingResource("Normal.joboptions")
            }
            try GhostscriptRuntimeConversion.convert(
                inputURL: request.fileURL,
                outputURL: outputURL,
                joboptionsURL: joboptionsURL,
                pageSelection: .first
            )
            guard let document = CGPDFDocument(outputURL as CFURL),
                  let page = document.page(at: 1)
            else {
                throw GhostscriptRuntimeConversion.Failure.missingResource("PDF page 1")
            }

            var pageBox = page.getBoxRect(.cropBox)
            if pageBox.isEmpty { pageBox = page.getBoxRect(.mediaBox) }
            let contextSize = Self.aspectFitSize(
                pageBox.size,
                maximumSize: request.maximumSize
            )
            let reply = QLThumbnailReply(contextSize: contextSize) { context in
                let drawingSize = CGSize(
                    width: contextSize.width * request.scale,
                    height: contextSize.height * request.scale
                )
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(origin: .zero, size: drawingSize))
                let transform = page.getDrawingTransform(
                    .cropBox,
                    rect: CGRect(origin: .zero, size: drawingSize),
                    rotate: 0,
                    preserveAspectRatio: true
                )
                context.concatenate(transform)
                context.drawPDFPage(page)
                return true
            }
            handler(reply, nil)
        } catch {
            Self.logger.error("Thumbnail generation failed: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }

    private static func aspectFitSize(_ size: CGSize, maximumSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return maximumSize }
        let scale = min(maximumSize.width / size.width, maximumSize.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static let logger = Logger(
        subsystem: "de.cafe-megabyte.iPS2PDF.MacOS.Thumbnail",
        category: "Thumbnail"
    )
}
