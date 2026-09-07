import Foundation

struct PDFProcessingReply: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case success, passwordRequired, invalidRequest, conformityUnsupported, failed, busy, cancelled, limitExceeded, unsupported
    }

    var version = PDFProcessingEnvelope.version
    let jobID: UUID
    let status: Status
    var outputBytes: Int64 = 0
    var warnings: [PDFProcessingWarning] = []
    var sharedResourcesFromEarlierPages = 0
    var detail: String = ""
}
