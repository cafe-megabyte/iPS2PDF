import Foundation
import XPC
#if os(macOS)
import PDFProcessingRuntime
#else
import PDFProcessingNative
#endif

final class PDFProcessingRequestHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var control: PDFNativeControl?
    private var cancelled = false
    private let jobRoot: URL?

    // A test host can supply its own private root. IPC payloads can supply only
    // UUIDs and never select a directory or an arbitrary input/output path.
    init(jobRoot: URL? = nil) { self.jobRoot = jobRoot }

    func cancel() {
        lock.lock()
        cancelled = true
        control?.cancel()
        lock.unlock()
    }

    func handle(_ envelope: XPCDictionary) -> XPCDictionary {
        let payload: String = envelope[PDFProcessingEnvelope.payload] ?? ""
        guard payload.utf8.count <= PDFProcessingEnvelope.maximumPayloadBytes,
              let data = payload.data(using: .utf8),
              let request = try? JSONDecoder().decode(PDFProcessingRequest.self, from: data) else {
            return encode(PDFProcessingReply(jobID: UUID(), status: .invalidRequest))
        }
        guard request.isValid else { return encode(PDFProcessingReply(jobID: request.jobID, status: .invalidRequest)) }
        do {
            guard let lease = try PDFNativeRequestLease.acquire(library: jobRoot?.deletingLastPathComponent()) else {
                return encode(PDFProcessingReply(jobID: request.jobID, status: .busy))
            }
            return try withExtendedLifetime(lease) {
                let job = try PDFProcessingJobDirectory.open(id: request.jobID, root: jobRoot)
                return try withExtendedLifetime(job) {
                    let native = try PDFNativeControl()
                    lock.lock()
                    control = native
                    if cancelled { native.cancel() }
                    lock.unlock()
                    defer { lock.lock(); control = nil; lock.unlock() }
                    let encodedPassword: String? = envelope[PDFProcessingEnvelope.password]
                    var password: String?
                    if let encodedPassword {
                        guard encodedPassword.utf8.count <= 8_192,
                              let bytes = Data(base64Encoded: encodedPassword), bytes.count <= 4_096,
                              !bytes.contains(0), let decoded = String(data: bytes, encoding: .utf8) else {
                            return encode(PDFProcessingReply(jobID: request.jobID, status: .invalidRequest))
                        }
                        password = decoded
                    }
                    var result = IPS2PDFProcessingResult()
                    switch request.operation {
                    case .removeMetadata:
                        ips2pdf_pdf_remove_metadata(job.inputURL.path, job.outputURL.path, password ?? "",
                                                    request.preserveConformity ? 1 : 0, native.pointer, &result)
                    case .compress:
                        let overrides = request.pageCompressionOverrides.map { item in
                            var value = IPS2PDFPageCompressionOverride()
                            value.page_index = Int32(item.pageIndex)
                            value.level = Int32(item.options.level.rawValue)
                            value.monochrome = item.options.colorMode == .blackAndWhite ? 1 : 0
                            value.threshold = Int32(item.options.threshold)
                            value.contrast = Int32(item.options.contrast)
                            return value
                        }
                        _ = overrides.withUnsafeBufferPointer { buffer in
                            ips2pdf_pdf_compress_preview(job.inputURL.path, job.outputURL.path, password ?? "",
                                                         Int32(request.compression.level.rawValue),
                                                         request.compression.colorMode == .blackAndWhite ? 1 : 0,
                                                         Int32(request.compression.threshold), Int32(request.compression.contrast),
                                                         buffer.baseAddress, UInt32(buffer.count),
                                                         Int32(request.previewPage ?? -1), native.pointer, &result)
                        }
                    case .extractResource:
                        ips2pdf_pdf_extract_resource(job.inputURL.path, job.outputURL.path, password ?? "",
                                                     request.resourceFormat ?? "", request.resourceFingerprint ?? "",
                                                     Int32(request.resourceWidth ?? 0), Int32(request.resourceHeight ?? 0),
                                                     Int32(request.resourceBitsPerComponent ?? 0), native.pointer, &result)
                    }
                    let status: PDFProcessingReply.Status = switch result.status {
                    case 0: .success
                    case 1: .passwordRequired
                    case 2: .invalidRequest
                    case 3: .conformityUnsupported
                    case 5: .busy
                    case 6: .cancelled
                    case 7: .limitExceeded
                    case 8: .unsupported
                    default: .failed
                    }
                    var warnings: [PDFProcessingWarning] = []
                    if result.warnings & 1 != 0 { warnings.append(.signaturesRemoved) }
                    if result.warnings & 2 != 0 { warnings.append(.protectionRemoved) }
                    if result.warnings & 4 != 0 { warnings.append(.signatureAppearanceMayDiffer) }
                    if result.warnings & 8 != 0 { warnings.append(.attachmentsRemoved) }
                    let detail = withUnsafeBytes(of: result.detail) { bytes in
                        String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
                    }
                    return encode(PDFProcessingReply(jobID: request.jobID, status: status,
                                                      outputBytes: Int64(clamping: result.output_bytes),
                                                      warnings: warnings,
                                                      sharedResourcesFromEarlierPages: Int(result.shared_resources_from_earlier_pages),
                                                      detail: detail))
                }
            }
        } catch {
            // Do not send file paths, passwords or document strings back as
            // third-party exception descriptions.
            return encode(PDFProcessingReply(jobID: request.jobID, status: .failed))
        }
    }

    private func encode(_ reply: PDFProcessingReply) -> XPCDictionary {
        var envelope = XPCDictionary()
        if let data = try? JSONEncoder().encode(reply), let payload = String(data: data, encoding: .utf8) {
            envelope[PDFProcessingEnvelope.response] = payload
        }
        return envelope
    }
}
