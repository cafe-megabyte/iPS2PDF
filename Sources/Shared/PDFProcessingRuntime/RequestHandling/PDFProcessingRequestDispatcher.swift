import Foundation
import XPC

/// Routes the independent processing protocol before Ghostscript's version
/// checks. Conversion and PDF editing share only process transport and a gate.
final class PDFProcessingRequestDispatcher: XPCPeerHandler, @unchecked Sendable {
    typealias Input = XPCDictionary
    typealias Output = XPCDictionary
    private let ghostscript = GhostscriptExtensionRequestHandler()
    private let processing = PDFProcessingRequestHandler()
    private let state = NSLock()
    private var runsGhostscript = false

    func cancelProcessing() { processing.cancel() }

    func handleIncomingRequest(_ request: XPCDictionary) -> XPCDictionary? { handle(request) }
    func handleCancellation(error: XPCRichError) {
        processing.cancel()
        state.lock()
        if runsGhostscript { ghostscript.handleCancellation(error: error) }
        state.unlock()
    }
    func handle(_ request: XPCDictionary, inputFileHandle: FileHandle? = nil) -> XPCDictionary {
        let operation: String = request[GhostscriptExtensionEnvelope.operation] ?? ""
        if operation == PDFProcessingEnvelope.operation { return processing.handle(request) }
        if operation != GhostscriptExtensionEnvelope.run { return ghostscript.handle(request, inputFileHandle: inputFileHandle) }
        do {
            guard let lease = try PDFNativeRequestLease.acquire() else { return unavailable(busy: true) }
            return withExtendedLifetime(lease) {
                state.lock(); runsGhostscript = true; state.unlock()
                defer { state.lock(); runsGhostscript = false; state.unlock() }
                return ghostscript.handle(request, inputFileHandle: inputFileHandle)
            }
        } catch { return unavailable(busy: false) }
    }
    private func unavailable(busy: Bool) -> XPCDictionary {
        var reply = XPCDictionary()
        reply[GhostscriptExtensionEnvelope.status] = Int64(-1)
        reply[GhostscriptExtensionEnvelope.message] = busy
            ? "Another PDF operation is already running. Try again when it finishes."
            : "The private PDF processing workspace is unavailable."
        return reply
    }
}
