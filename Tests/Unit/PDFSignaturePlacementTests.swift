import XCTest

final class PDFSignaturePlacementTests: XCTestCase {
    func testSignatureRequestRequiresOnlyValidPlacements() {
        let jobID = UUID()
        let placement = PDFSignaturePlacement(pageIndex: 0, x: 12.5, y: 24.5)
        let valid = PDFProcessingRequest(jobID: jobID, operation: .addSignatures,
                                         preserveConformity: false, compression: .init(),
                                         signaturePlacements: [placement])
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(placement.fontSize, 50)

        let empty = PDFProcessingRequest(jobID: jobID, operation: .addSignatures,
                                         preserveConformity: false, compression: .init())
        XCTAssertFalse(empty.isValid)

        for invalid in [
            PDFSignaturePlacement(pageIndex: -1, x: 0, y: 0),
            PDFSignaturePlacement(pageIndex: 0, x: .nan, y: 0),
            PDFSignaturePlacement(pageIndex: 0, x: 0, y: .infinity),
            PDFSignaturePlacement(pageIndex: 0, x: 0, y: 0, fontSize: 4.9),
            PDFSignaturePlacement(pageIndex: 0, x: 0, y: 0, fontSize: 500.1),
        ] {
            var request = valid
            request.signaturePlacements = [invalid]
            XCTAssertFalse(request.isValid)
        }
    }

    func testOtherOperationsRejectSignaturePlacements() {
        let request = PDFProcessingRequest(
            jobID: UUID(), operation: .removeMetadata, preserveConformity: false,
            compression: .init(),
            signaturePlacements: [PDFSignaturePlacement(pageIndex: 0, x: 0, y: 0)]
        )
        XCTAssertFalse(request.isValid)
    }
}
