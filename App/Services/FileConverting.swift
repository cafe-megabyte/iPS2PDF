import Foundation

protocol FileConverting: Sendable {
    func convert(sourceURL: URL, outputURL: URL, pdfVersion: PDFVersion) async throws
}
