import Foundation

struct PDFSignaturePlacement: Codable, Hashable, Identifiable, Sendable {
    static let defaultFontSize = 50.0
    static let minimumFontSize = 5.0
    static let maximumFontSize = 500.0

    var id: UUID
    var pageIndex: Int
    /// Baseline origin in unrotated PDF page user space.
    var x: Double
    var y: Double
    var fontSize: Double

    init(id: UUID = UUID(), pageIndex: Int, x: Double, y: Double,
         fontSize: Double = defaultFontSize) {
        self.id = id
        self.pageIndex = pageIndex
        self.x = x
        self.y = y
        self.fontSize = fontSize
    }

    var isValid: Bool {
        (0...Int(Int32.max)).contains(pageIndex) && x.isFinite && y.isFinite &&
            fontSize.isFinite && (Self.minimumFontSize...Self.maximumFontSize).contains(fontSize)
    }
}
