import CoreGraphics
import XCTest

final class PDFCompressionOptionsTests: XCTestCase {
    func testContrastRangeAndDefault() {
        var options = PDFCompressionOptions()
        XCTAssertEqual(options.contrast, 25)

        options.contrast = 0
        XCTAssertTrue(options.isValid)
        options.contrast = 100
        XCTAssertTrue(options.isValid)
        options.contrast = -1
        XCTAssertFalse(options.isValid)
        options.contrast = 101
        XCTAssertFalse(options.isValid)
    }

    func testPaperCleanupRangeAndDefault() {
        var options = PDFCompressionOptions()
        XCTAssertEqual(options.paperCleanup, 50)

        options.paperCleanup = 0
        XCTAssertTrue(options.isValid)
        options.paperCleanup = 100
        XCTAssertTrue(options.isValid)
        options.paperCleanup = -1
        XCTAssertFalse(options.isValid)
        options.paperCleanup = 101
        XCTAssertFalse(options.isValid)
    }

    func testPaperAreaSamplingKeepsMultipleBackgroundColorsAndRejectsInk() throws {
        let width = 60
        let height = 40
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let greenPattern = (x / 5 + y / 5).isMultiple(of: 2)
                pixels[offset] = greenPattern ? 205 : 247
                pixels[offset + 1] = greenPattern ? 232 : 247
                pixels[offset + 2] = greenPattern ? 218 : 247
                pixels[offset + 3] = 255
                if x >= 24 && x < 36 && y >= 10 && y < 30 {
                    pixels[offset] = 12
                    pixels[offset + 1] = 12
                    pixels[offset + 2] = 12
                }
            }
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                     CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )!
        let sample = try XCTUnwrap(PDFPaperSampleAnalyzer.analyze(
            image, pageIndex: 4, normalizedPoint: CGPoint(x: 0.25, y: 0.75)
        ))
        XCTAssertTrue(sample.isValid)
        XCTAssertEqual(sample.pageIndex, 4)
        XCTAssertGreaterThanOrEqual(sample.colors.count, 2)
        let sampledLuminance = sample.colors.map { color in
            0.2126 * Double(color.red) + 0.7152 * Double(color.green) +
                0.0722 * Double(color.blue)
        }
        XCTAssertTrue(sampledLuminance.allSatisfy { $0 > 150 })

        var options = PDFCompressionOptions()
        options.paperSample = sample
        XCTAssertTrue(options.isValid)
        let decoded = try JSONDecoder().decode(
            PDFCompressionOptions.self, from: JSONEncoder().encode(options)
        )
        XCTAssertEqual(decoded, options)
    }
}
