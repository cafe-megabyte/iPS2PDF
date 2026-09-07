import Foundation
import CryptoKit
import PDFKit
import XPC

@main
struct PDFProcessingIPCSmoke {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw NSError(domain: "PDFProcessingIPCSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = directory.appendingPathComponent("PDFProcessingJobs", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func send(_ job: PDFProcessingJobDirectory, password: String? = nil,
                  version: Int = PDFProcessingEnvelope.version, operation: PDFProcessingRequest.Operation = .removeMetadata,
                  options: PDFCompressionOptions = .init(), previewPage: Int? = nil,
                  pageOverrides: [PDFPageCompressionOverride] = [],
                  resource: PDFExtractableResource? = nil, handler: PDFProcessingRequestHandler? = nil) throws -> PDFProcessingReply {
            var envelope = XPCDictionary()
            let request = PDFProcessingRequest(version: version, jobID: job.id, operation: operation,
                                                preserveConformity: false, compression: options,
                                                pageCompressionOverrides: pageOverrides, previewPage: previewPage,
                                                resourceFingerprint: resource?.fingerprint,
                                                resourceFormat: resource?.format.rawValue,
                                                resourceWidth: resource?.pixelWidth,
                                                resourceHeight: resource?.pixelHeight,
                                                resourceBitsPerComponent: resource?.bitsPerComponent)
            envelope[GhostscriptExtensionEnvelope.operation] = PDFProcessingEnvelope.operation
            envelope[PDFProcessingEnvelope.payload] = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
            if let password { envelope[PDFProcessingEnvelope.password] = Data(password.utf8).base64EncodedString() }
            // Exercise the actual Mac wire codec on both sides of the helper,
            // including UTF-8 passwords kept out of the Codable job request.
            let delivered = try MacOSXPCMessageCodec.decode(MacOSXPCMessageCodec.encode(envelope))
            let response = (handler ?? PDFProcessingRequestHandler(jobRoot: root)).handle(delivered)
            let decoded = try MacOSXPCMessageCodec.decode(MacOSXPCMessageCodec.encode(response))
            let payload: String = decoded[PDFProcessingEnvelope.response] ?? ""
            let reply = try JSONDecoder().decode(PDFProcessingReply.self, from: Data(payload.utf8))
            try require(reply.jobID == job.id && reply.version == PDFProcessingEnvelope.version, "Reply identity changed")
            return reply
        }
        func staged(_ name: String) throws -> PDFProcessingJobDirectory {
            let job = try PDFProcessingJobDirectory.create(root: root)
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: job.inputURL)
            return job
        }
        let job = try staged("InfoPlain.pdf")
        let original = try Data(contentsOf: job.inputURL)
        let finished = try send(job)
        try require(finished.status == .success && finished.outputBytes > 0, "Metadata request did not succeed")
        let pdf = PDFDocument(url: job.outputURL)
        try require(pdf?.pageCount == 1 && pdf?.documentAttributes?[PDFDocumentAttribute.titleAttribute] == nil, "Result did not reopen without title")
        try require(try Data(contentsOf: job.inputURL) == original, "Input changed")
        let candidate = try Data(contentsOf: job.outputURL)
        try require(try send(job).status == .failed, "Existing output was overwritten")
        try require(try Data(contentsOf: job.outputURL) == candidate, "Existing output canary changed")

        let versionJob = try staged("InfoPlain.pdf")
        try require(try send(versionJob, version: 99).status == .invalidRequest, "Invalid protocol accepted")
        try require(try send(versionJob, password: "bad\0password").status == .invalidRequest, "C-string truncation password accepted")
        let cancelled = PDFProcessingRequestHandler(jobRoot: root)
        cancelled.cancel()
        try require(try send(versionJob, handler: cancelled).status == .cancelled, "Pre-cancelled request ran")
        try require(!FileManager.default.fileExists(atPath: versionJob.outputURL.path), "Cancelled output remained")
        var lease = try PDFNativeRequestLease.acquire(library: directory)
        try require(lease != nil, "Could not acquire test engine gate")
        try require(try send(versionJob).status == .busy, "Overlapping native operation ran")
        lease = nil
        try require(try send(versionJob).status == .success, "Engine gate did not recover")

        let protected = try staged("InfoEncrypted-AES-256.pdf")
        try require(try send(protected, password: "wrong-password").status == .passwordRequired, "Wrong password accepted")
        try require(!FileManager.default.fileExists(atPath: protected.outputURL.path), "Password failure created output")
        for page: Int? in [nil, 0] {
            let compression = try staged("InfoICC.pdf")
            let options = page == nil
                ? PDFCompressionOptions(level: .strong, colorMode: .blackAndWhite, threshold: 60)
                : PDFCompressionOptions(level: .balanced, colorMode: .color, contrast: 20)
            let response = try send(compression, operation: .compress,
                                    options: options, previewPage: page,
                                    pageOverrides: [PDFPageCompressionOverride(pageIndex: 0, options: options)])
            try require(response.status == .success && response.outputBytes > 0, "Compression IPC did not return a candidate")
            try require(PDFDocument(url: compression.outputURL)?.pageCount == 1, "Compression IPC result did not reopen")
        }
        let invalidOverrides = try staged("InfoPlain.pdf")
        let repeated = PDFPageCompressionOverride(pageIndex: 0, options: .init())
        try require(try send(invalidOverrides, operation: .compress,
                             pageOverrides: [repeated, repeated]).status == .invalidRequest,
                    "Duplicate page compression overrides were accepted")
        try require(try send(invalidOverrides, operation: .compress,
                             pageOverrides: [PDFPageCompressionOverride(pageIndex: 1, options: .init())]).status == .failed,
                    "Out-of-range page compression override was accepted")
        try require(!FileManager.default.fileExists(atPath: invalidOverrides.outputURL.path),
                    "Invalid page compression override created output")
        let invalidPreview = try staged("InfoPlain.pdf")
        try require(try send(invalidPreview, previewPage: 0).status == .invalidRequest, "Metadata accepted a compression-only preview parameter")

        let iccReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoICC.pdf"), fileName: "InfoICC.pdf", password: nil)
        let iccResource = try iccReport.exportableResources.first { $0.kind == .iccProfile }.unwrap("ICC resource missing")
        let iccJob = try staged("InfoICC.pdf")
        let iccReply = try send(iccJob, operation: .extractResource, resource: iccResource)
        try require(iccReply.status == .success, "ICC extraction failed")
        let iccData = try Data(contentsOf: iccJob.outputURL)
        let iccDigest = SHA256.hash(data: iccData).map { String(format: "%02x", $0) }.joined()
        try require(iccDigest == iccResource.fingerprint, "ICC bytes changed during extraction")

        let imageReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoInlineImage.pdf"), fileName: "InfoInlineImage.pdf", password: nil)
        let imageResource = try imageReport.exportableResources.first { $0.kind == .image }.unwrap("Inline image resource missing")
        let imageJob = try staged("InfoInlineImage.pdf")
        let imageReply = try send(imageJob, operation: .extractResource, resource: imageResource)
        try require(imageReply.status == .success, "Inline image extraction failed")
        try require(try Data(contentsOf: imageJob.outputURL).starts(with: [0x89, 0x50, 0x4e, 0x47]), "Inline image is not PNG")

        let attachmentReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoAttachment.pdf"), fileName: "InfoAttachment.pdf", password: nil)
        let attachment = try attachmentReport.exportableResources.first { $0.kind == .attachment }.unwrap("Attachment resource missing")
        let attachmentJob = try staged("InfoAttachment.pdf")
        let attachmentReply = try send(attachmentJob, operation: .extractResource, resource: attachment)
        try require(attachmentReply.status == .success, "Attachment extraction failed")
        try require(try Data(contentsOf: attachmentJob.outputURL).starts(with: Data("iPS2PDF embedded attachment".utf8)), "Attachment bytes changed")

        let fontReport = try PDFInspectionService.inspect(url: fixtures.appendingPathComponent("InfoEmbeddedSubset.pdf"), fileName: "InfoEmbeddedSubset.pdf", password: nil)
        let font = try fontReport.exportableResources.first { $0.kind == .font }.unwrap("Embedded font resource missing")
        let fontJob = try staged("InfoEmbeddedSubset.pdf")
        let fontReply = try send(fontJob, operation: .extractResource, resource: font)
        try require(fontReply.status == .success, "Embedded font extraction failed")
        let fontData = try Data(contentsOf: fontJob.outputURL)
        if font.format == .type1 {
            try require(fontData.starts(with: [0x80, 0x01]), "Type 1 font was not reconstructed as PFB")
        } else {
            let fontDigest = SHA256.hash(data: fontData).map { String(format: "%02x", $0) }.joined()
            try require(fontDigest == font.fingerprint, "Embedded font bytes changed during extraction")
        }
        print("PASS PDF helper contract: wire codec, native result, original preservation, exclusive output, versions, cancellation, serialization, password failures, compression, previews, ICC, image, attachment and font extraction")
    }
}

private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw NSError(domain: "PDFProcessingIPCSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: message]) }
        return self
    }
}
