import XCTest

final class PostScriptOutputNamingTests: XCTestCase {
    func testPDFAndEPSUseTheOriginalStem() {
        XCTAssertEqual(PostScriptOutputNaming.filename(for: "Document.pdf"), "Document.ps")
        XCTAssertEqual(PostScriptOutputNaming.filename(for: "Artwork.EPS"), "Artwork.ps")
    }

    func testPostScriptInputAvoidsOverwritingItsSourceName() {
        XCTAssertEqual(
            PostScriptOutputNaming.filename(for: "Already.ps"),
            "Already-converted.ps"
        )
        XCTAssertEqual(
            PostScriptOutputNaming.filename(for: "Already.PS"),
            "Already-converted.ps"
        )
    }

    func testArbitraryInputUsesItsStem() {
        XCTAssertEqual(PostScriptOutputNaming.filename(for: "Drawing.xyz"), "Drawing.ps")
    }
}
