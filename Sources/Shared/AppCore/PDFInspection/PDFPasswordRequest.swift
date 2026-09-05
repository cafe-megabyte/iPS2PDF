import Foundation

struct PDFPasswordRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let wasIncorrect: Bool
}
