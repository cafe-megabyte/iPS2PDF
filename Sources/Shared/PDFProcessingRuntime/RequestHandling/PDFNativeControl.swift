import Foundation
#if os(macOS)
import PDFProcessingRuntime
#else
import PDFProcessingNative
#endif

/// Kept alive by both the synchronous native call and the cancellation owner.
final class PDFNativeControl: @unchecked Sendable {
    let pointer: OpaquePointer
    init() throws {
        guard let pointer = ips2pdf_pdf_control_create(15 * 60 * 1_000, 1_073_741_824, 2_147_483_648) else {
            throw CocoaError(.coderInvalidValue)
        }
        self.pointer = pointer
    }
    func cancel() { ips2pdf_pdf_control_cancel(pointer) }
    deinit { ips2pdf_pdf_control_destroy(pointer) }
}
