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
}
