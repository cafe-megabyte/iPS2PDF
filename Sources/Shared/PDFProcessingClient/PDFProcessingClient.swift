import Foundation
@preconcurrency import XPC

struct PDFProcessingClient: Sendable {
    func process(_ revision: PDFEditingRevision, operation: PDFProcessingRequest.Operation,
                 preserveConformity: Bool, compression: PDFCompressionOptions = .init(),
                 password: String?, previewPage: Int? = nil) async throws -> PDFEditingRevision {
        guard revision.byteCount <= 1_073_741_824 else { throw PDFProcessingError.limitExceeded }
        try Task.checkCancellation()
        let job = try await Task.detached(priority: .userInitiated) {
            try? PDFProcessingJobDirectory.removeStaleJobs()
            let job = try PDFProcessingJobDirectory.create()
            try FileManager.default.copyItem(at: revision.input.url, to: job.inputURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: job.inputURL.path)
            return job
        }.value
        // A sender lease survives the await and snapshot copy; the helper owns
        // an independent lease until its native call has actually returned.
        defer { withExtendedLifetime(job) {} }
        try Task.checkCancellation()
        let request = PDFProcessingRequest(jobID: job.id, operation: operation,
                                           preserveConformity: preserveConformity, compression: compression, previewPage: previewPage)
        guard request.isValid else { throw PDFProcessingError.failed }
        var envelope = XPCDictionary()
        envelope[GhostscriptExtensionEnvelope.operation] = PDFProcessingEnvelope.operation
        envelope[PDFProcessingEnvelope.payload] = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        if let password { envelope[PDFProcessingEnvelope.password] = Data(password.utf8).base64EncodedString() }
        var reply: PDFProcessingReply
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while true {
            let response = try await GhostscriptExtensionClient().sendPDFProcessing(envelope)
            try Task.checkCancellation()
            let payload: String = response[PDFProcessingEnvelope.response] ?? ""
            guard payload.utf8.count <= PDFProcessingEnvelope.maximumPayloadBytes,
                  let decoded = try? JSONDecoder().decode(PDFProcessingReply.self, from: Data(payload.utf8)),
                  decoded.version == PDFProcessingEnvelope.version, decoded.jobID == job.id else {
                throw PDFProcessingError.invalidReply
            }
            reply = decoded
            // Closing a cancelled XPC connection can precede the native
            // worker's cooperative exit. Allow that worker to release its
            // cross-process lease before starting the newest preview.
            guard reply.status == .busy, ContinuousClock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        switch reply.status {
        case .success: break
        case .passwordRequired: throw PDFProcessingError.passwordRequired
        case .conformityUnsupported: throw PDFProcessingError.conformityUnsupported(reply.detail)
        case .unsupported: throw PDFProcessingError.unsupported(reply.detail)
        case .busy: throw PDFProcessingError.busy
        case .cancelled: throw CancellationError()
        case .limitExceeded: throw PDFProcessingError.limitExceeded
        case .invalidRequest, .failed: throw PDFProcessingError.failed
        }
        let candidate = try await Task.detached(priority: .userInitiated) {
            let properties = try job.outputURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard properties.isRegularFile == true, properties.isSymbolicLink != true,
                  reply.outputBytes > 0, reply.outputBytes <= 2_147_483_648,
                  Int64(properties.fileSize ?? 0) == reply.outputBytes else { throw PDFProcessingError.invalidReply }
            let snapshot = try PDFInspectionInput(sourceURL: job.outputURL, displayFileName: revision.input.fileName)
            return try PDFEditingRevision(input: snapshot, warnings: reply.warnings)
        }.value
        try Task.checkCancellation()
        return candidate
    }
}
