import Foundation

enum PDFProcessingEnvelope {
    // A separate protocol version lets processing evolve without changing
    // Ghostscript's conversion/joboptions messages.
    static let version = 1
    static let operation = "pdfProcessing"
    static let payload = "pdfProcessingPayload"
    // XPC C strings cannot carry embedded NUL. Encode UTF-8 before transport
    // so the helper can reject unsupported passwords without truncating them.
    static let password = "pdfProcessingPasswordUTF8"
    static let response = "pdfProcessingResponse"
    static let maximumPayloadBytes = 64 * 1024
}
