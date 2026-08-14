import Foundation

enum PDFVersion: String, CaseIterable, Identifiable, Sendable {
    case v12 = "1.2"
    case v13 = "1.3"
    case v14 = "1.4"

    var id: String { rawValue }
}
