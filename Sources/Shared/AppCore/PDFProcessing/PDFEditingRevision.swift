import Foundation

struct PDFEditingRevision: Identifiable, Sendable {
    let id: UUID
    let input: PDFInspectionInput
    let byteCount: Int64
    let warnings: [PDFProcessingWarning]

    init(input: PDFInspectionInput, warnings: [PDFProcessingWarning] = []) throws {
        id = UUID()
        self.input = input
        byteCount = Int64(try input.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        self.warnings = warnings
    }
}
