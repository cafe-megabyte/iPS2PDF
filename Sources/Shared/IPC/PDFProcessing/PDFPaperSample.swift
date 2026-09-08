import Foundation

struct PDFPaperSample: Codable, Equatable, Sendable {
    struct Color: Codable, Equatable, Sendable {
        let red: Int
        let green: Int
        let blue: Int

        var isValid: Bool {
            (0...255).contains(red) && (0...255).contains(green) &&
                (0...255).contains(blue)
        }
    }

    let pageIndex: Int
    let normalizedX: Double
    let normalizedY: Double
    let colors: [Color]

    var isValid: Bool {
        (0...Int(Int32.max)).contains(pageIndex) && normalizedX.isFinite &&
            normalizedY.isFinite && (0...1).contains(normalizedX) &&
            (0...1).contains(normalizedY) && (1...3).contains(colors.count) &&
            colors.allSatisfy(\.isValid)
    }
}
